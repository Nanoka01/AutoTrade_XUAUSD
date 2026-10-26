"""Discord bot that monitors and controls the XauScalper EA.

Run:  python main.py
"""
from __future__ import annotations

import asyncio
import datetime as dt
import logging
import time
from zoneinfo import ZoneInfo

import aiohttp
import discord
from discord import app_commands
from discord.ext import tasks

import config
from bridge import Bridge
from db import Summary, TradeDb

log = logging.getLogger("xauscalper")

COLOR_INFO = 0x3B82F6
COLOR_GOOD = 0x16A34A
COLOR_BAD = 0xDC2626
COLOR_WARN = 0xF59E0B

STATE_TH = {"running": "🟢 กำลังทำงาน", "paused": "⏸️ หยุดชั่วคราว", "halted": "🛑 หยุดฉุกเฉิน"}


class ConfirmView(discord.ui.View):
    """Two buttons; only the owner can press them."""

    def __init__(self, owner_id: int):
        super().__init__(timeout=30)
        self.owner_id = owner_id
        self.confirmed: bool | None = None

    async def interaction_check(self, interaction: discord.Interaction) -> bool:
        return interaction.user.id == self.owner_id

    @discord.ui.button(label="ยืนยัน", style=discord.ButtonStyle.danger)
    async def confirm(self, interaction: discord.Interaction, button: discord.ui.Button):
        self.confirmed = True
        await interaction.response.defer()
        self.stop()

    @discord.ui.button(label="ยกเลิก", style=discord.ButtonStyle.secondary)
    async def cancel(self, interaction: discord.Interaction, button: discord.ui.Button):
        self.confirmed = False
        await interaction.response.defer()
        self.stop()


class XauBot(discord.Client):
    def __init__(self, cfg: config.Config):
        super().__init__(intents=discord.Intents.default())
        self.cfg = cfg
        self.bridge = Bridge(cfg.bridge_dir)
        self.db = TradeDb(cfg.db_path)
        self.tree = app_commands.CommandTree(self)
        self.pending: dict[str, asyncio.Future] = {}
        self.heartbeat_lost = False
        self.broker_lost = False
        self.http_session: aiohttp.ClientSession | None = None
        register_commands(self)

    async def setup_hook(self) -> None:
        guild = discord.Object(id=self.cfg.guild_id)
        self.tree.copy_global_to(guild=guild)
        await self.tree.sync(guild=guild)
        self.http_session = aiohttp.ClientSession()
        self.daily_report.change_interval(
            time=dt.time(hour=self.cfg.report_hour, tzinfo=ZoneInfo(self.cfg.timezone))
        )
        self.poll_events.start()
        self.check_heartbeat.start()
        self.daily_report.start()

    async def close(self) -> None:
        if self.http_session:
            await self.http_session.close()
        await super().close()

    async def on_ready(self) -> None:
        log.info("Logged in as %s; bridge folder %s", self.user, self.bridge.base)
        await self.send(self.cfg.channel_alerts, f"🤖 Bot ออนไลน์แล้ว (โฟลเดอร์: `{self.bridge.base}`)")

    # ---------- helpers ----------
    async def send(self, channel_id: int, content: str | None = None, embed: discord.Embed | None = None,
                   mention: bool = False) -> None:
        channel = self.get_channel(channel_id)
        if channel is None:
            log.warning("Channel %s not found", channel_id)
            return
        if mention:
            content = f"<@{self.cfg.owner_id}> {content or ''}"
        await channel.send(content=content, embed=embed)

    async def run_command(self, cmd: str, arg: str = "", timeout: float = 15) -> dict | None:
        """Sends a command to the EA and waits for its cmd_result event."""
        cmd_id = self.bridge.send_command(cmd, arg)
        fut = asyncio.get_running_loop().create_future()
        self.pending[cmd_id] = fut
        try:
            return await asyncio.wait_for(fut, timeout)
        except asyncio.TimeoutError:
            return None
        finally:
            self.pending.pop(cmd_id, None)

    # ---------- background loops ----------
    @tasks.loop(seconds=2)
    async def poll_events(self) -> None:
        for event in self.bridge.pop_events():
            try:
                await self.route_event(event)
            except Exception:
                log.exception("Failed to handle event %s", event)

    @poll_events.before_loop
    async def _wait_ready_events(self) -> None:
        await self.wait_until_ready()

    async def route_event(self, event: dict) -> None:
        etype = event.get("type", "")
        level = event.get("level", "info")
        msg = event.get("msg", "")
        data = event.get("data", {})

        if etype == "cmd_result":
            fut = self.pending.get(data.get("id", ""))
            if fut and not fut.done():
                fut.set_result(event)
            return

        if etype == "trade_open":
            embed = discord.Embed(title=f"📈 เปิด {data.get('side')} {data.get('volume')} lot", color=COLOR_INFO)
            embed.add_field(name="ราคา", value=str(data.get("price")))
            embed.add_field(name="SL", value=str(data.get("sl")))
            embed.add_field(name="TP", value=str(data.get("tp")))
            embed.set_footer(text=f"#{data.get('ticket')}")
            await self.send(self.cfg.channel_trades, embed=embed)
            return

        if etype == "trade_close":
            self.db.add_close(event)
            profit = float(data.get("profit", 0))
            embed = discord.Embed(
                title=f"{'✅' if profit >= 0 else '❌'} ปิด {data.get('side')} {data.get('volume')} lot ({data.get('reason')})",
                description=f"กำไร/ขาดทุน **{profit:+.2f} {data.get('currency', '')}**",
                color=COLOR_GOOD if profit >= 0 else COLOR_BAD,
            )
            embed.add_field(name="ราคาปิด", value=str(data.get("price")))
            embed.set_footer(text=f"#{data.get('ticket')}")
            await self.send(self.cfg.channel_trades, embed=embed)
            return

        icon = {"critical": "🚨", "warning": "⚠️"}.get(level, "ℹ️")
        await self.send(self.cfg.channel_alerts, f"{icon} `{etype}` {msg}", mention=(level == "critical"))

    @tasks.loop(seconds=30)
    async def check_heartbeat(self) -> None:
        status = self.bridge.read_status()
        age = self.bridge.status_age(status)
        stale = age is None or age > self.cfg.heartbeat_timeout
        if stale and not self.heartbeat_lost:
            self.heartbeat_lost = True
            when = "ยังไม่เคยได้รับสถานะ" if age is None else f"เงียบไป {int(age)} วินาที"
            await self.send(self.cfg.channel_alerts,
                            f"🚨 ไม่ได้รับสัญญาณจาก EA ({when}) ตรวจว่า MT5 เปิดอยู่และ EA ยังติดอยู่บนกราฟ",
                            mention=True)
        elif not stale and self.heartbeat_lost:
            self.heartbeat_lost = False
            await self.send(self.cfg.channel_alerts, "✅ EA กลับมาส่งสัญญาณแล้ว")

        if status and not stale:
            connected = status.get("connected", True)
            if not connected and not self.broker_lost:
                await self.send(self.cfg.channel_alerts, "⚠️ MT5 หลุดการเชื่อมต่อกับโบรกเกอร์", mention=True)
            elif connected and self.broker_lost:
                await self.send(self.cfg.channel_alerts, "✅ MT5 เชื่อมต่อโบรกเกอร์ได้แล้ว")
            self.broker_lost = not connected
            if self.cfg.healthcheck_url and self.http_session:
                try:
                    await self.http_session.get(self.cfg.healthcheck_url, timeout=aiohttp.ClientTimeout(total=10))
                except Exception as exc:  # network hiccups must not stop the loop
                    log.warning("Healthcheck ping failed: %s", exc)

    @check_heartbeat.before_loop
    async def _wait_ready_hb(self) -> None:
        await self.wait_until_ready()

    @tasks.loop(time=dt.time(hour=23))
    async def daily_report(self) -> None:
        await self.send(self.cfg.channel_reports, embed=self.report_embed("สรุปรายวัน", time.time() - 86400))

    @daily_report.before_loop
    async def _wait_ready_report(self) -> None:
        await self.wait_until_ready()

    # ---------- embeds ----------
    def status_embed(self) -> discord.Embed:
        s = self.bridge.read_status()
        age = self.bridge.status_age(s)
        if not s:
            return discord.Embed(title="ไม่พบสถานะจาก EA", description="EA ยังไม่ได้รัน หรือโฟลเดอร์ bridge ไม่ตรงกัน",
                                 color=COLOR_BAD)
        cur = s.get("currency", "")
        embed = discord.Embed(
            title=f"{s.get('symbol')} · {STATE_TH.get(s.get('state'), s.get('state'))}",
            description=(f"บัญชี {s.get('login')} ({'Demo' if s.get('demo') else '**REAL**'}) · "
                         f"อัปเดตเมื่อ {int(age or 0)} วินาทีก่อน"),
            color=COLOR_GOOD if s.get("state") == "running" else COLOR_WARN,
        )
        embed.add_field(name="Balance", value=f"{s.get('balance', 0):,.2f} {cur}")
        embed.add_field(name="Equity", value=f"{s.get('equity', 0):,.2f} {cur}")
        embed.add_field(name="Margin level", value=f"{s.get('margin_level', 0):,.0f}%")
        embed.add_field(name="วันนี้", value=f"{s.get('daily_pnl_pct', 0):+.2f}%")
        embed.add_field(name="Drawdown", value=f"{s.get('dd_pct', 0):.2f}% / {s.get('max_dd_pct', 0):.1f}%")
        embed.add_field(name="Risk ต่อไม้", value=f"{s.get('risk_pct', 0):.2f}%")
        trend = {1: "ขาขึ้น", -1: "ขาลง"}.get(s.get("trend"), "ไม่ชัด")
        embed.add_field(name="เทรนด์", value=trend)
        embed.add_field(name="Spread", value=f"{s.get('spread')} points")
        embed.add_field(name="ไม้วันนี้", value=f"{s.get('trades_today')} (แพ้ติด {s.get('consec_losses')})")
        embed.add_field(name="ไม้ที่เปิดอยู่", value=str(len(s.get("positions", []))))
        if not s.get("algo_trading", True):
            embed.add_field(name="⚠️", value="ปุ่ม Algo Trading ใน MT5 ปิดอยู่", inline=False)
        embed.set_footer(text=f"เวลา server {s.get('server_time')}")
        return embed

    def report_embed(self, title: str, since: float) -> discord.Embed:
        sm: Summary = self.db.summary(since)
        embed = discord.Embed(title=f"📊 {title}", color=COLOR_GOOD if sm.net >= 0 else COLOR_BAD)
        if sm.trades == 0:
            embed.description = "ไม่มีไม้ที่ปิดในช่วงนี้"
            return embed
        pf = f"{sm.profit_factor:.2f}" if sm.profit_factor is not None else "∞"
        embed.add_field(name="จำนวนไม้", value=str(sm.trades))
        embed.add_field(name="Win rate", value=f"{sm.win_rate:.1f}%")
        embed.add_field(name="Profit factor", value=pf)
        embed.add_field(name="กำไรสุทธิ", value=f"{sm.net:+.2f}")
        embed.add_field(name="ไม้ดีสุด", value=f"{sm.best:+.2f}")
        embed.add_field(name="ไม้แย่สุด", value=f"{sm.worst:+.2f}")
        s = self.bridge.read_status()
        if s:
            embed.set_footer(text=f"Equity {s.get('equity', 0):,.2f} · DD {s.get('dd_pct', 0):.2f}%")
        return embed


def register_commands(bot: XauBot) -> None:
    tree = bot.tree
    cfg = bot.cfg

    async def owner_only(interaction: discord.Interaction, control: bool) -> bool:
        if interaction.user.id != cfg.owner_id:
            await interaction.response.send_message("คุณไม่มีสิทธิ์ใช้คำสั่งนี้", ephemeral=True)
            return False
        if control and interaction.channel_id != cfg.channel_control:
            await interaction.response.send_message(f"ใช้คำสั่งนี้ได้เฉพาะใน <#{cfg.channel_control}>", ephemeral=True)
            return False
        return True

    async def reply_result(interaction: discord.Interaction, result: dict | None, edit: bool) -> None:
        if result is None:
            text = "⌛ EA ไม่ตอบภายใน 15 วินาที (MT5 หรือ EA อาจไม่ได้รัน)"
        else:
            ok = result.get("data", {}).get("ok", False)
            text = f"{'✅' if ok else '⚠️'} {result.get('msg')}"
        if edit:
            await interaction.edit_original_response(content=text, view=None)
        else:
            await interaction.followup.send(text)

    async def confirmed(interaction: discord.Interaction, question: str) -> bool:
        view = ConfirmView(cfg.owner_id)
        await interaction.response.send_message(question, view=view)
        await view.wait()
        if not view.confirmed:
            await interaction.edit_original_response(content="ยกเลิกแล้ว", view=None)
            return False
        await interaction.edit_original_response(content="⏳ กำลังส่งคำสั่ง...", view=None)
        return True

    @tree.command(name="status", description="ดูสถานะบัญชีและ EA")
    async def status_cmd(interaction: discord.Interaction):
        if not await owner_only(interaction, control=False):
            return
        await interaction.response.send_message(embed=bot.status_embed())

    @tree.command(name="positions", description="ดูไม้ที่เปิดอยู่")
    async def positions_cmd(interaction: discord.Interaction):
        if not await owner_only(interaction, control=False):
            return
        s = bot.bridge.read_status() or {}
        positions = s.get("positions", [])
        if not positions:
            await interaction.response.send_message("ไม่มีไม้ที่เปิดอยู่")
            return
        lines = [
            f"`#{p['ticket']}` {p['side']} {p['volume']} @ {p['open']} · SL {p['sl']} · TP {p['tp']} · "
            f"**{p['profit']:+.2f}**"
            for p in positions
        ]
        await interaction.response.send_message("\n".join(lines))

    @tree.command(name="report", description="สรุปผลการเทรด")
    @app_commands.choices(period=[
        app_commands.Choice(name="วันนี้ (24 ชม.)", value="day"),
        app_commands.Choice(name="7 วัน", value="week"),
        app_commands.Choice(name="30 วัน", value="month"),
    ])
    async def report_cmd(interaction: discord.Interaction, period: app_commands.Choice[str]):
        if not await owner_only(interaction, control=False):
            return
        seconds = {"day": 86400, "week": 7 * 86400, "month": 30 * 86400}[period.value]
        await interaction.response.send_message(embed=bot.report_embed(period.name, time.time() - seconds))

    @tree.command(name="pause", description="หยุดเปิดไม้ใหม่ (ไม้ที่เปิดอยู่ยังถูกดูแลต่อ)")
    async def pause_cmd(interaction: discord.Interaction):
        if not await owner_only(interaction, control=True):
            return
        await interaction.response.defer(thinking=True)
        await reply_result(interaction, await bot.run_command("pause"), edit=False)

    @tree.command(name="resume", description="ให้ EA กลับมาเปิดไม้ใหม่")
    async def resume_cmd(interaction: discord.Interaction):
        if not await owner_only(interaction, control=True):
            return
        if not await confirmed(interaction, "ให้ EA กลับมาเทรดใช่ไหม? (ถ้าหยุดเพราะ drawdown จุดสูงสุดของ equity จะถูกรีเซ็ต)"):
            return
        await reply_result(interaction, await bot.run_command("resume"), edit=True)

    @tree.command(name="close", description="ปิดไม้ตามเลข ticket หรือ all")
    @app_commands.describe(target="เลข ticket หรือ all")
    async def close_cmd(interaction: discord.Interaction, target: str):
        if not await owner_only(interaction, control=True):
            return
        target = target.strip().lower()
        if target != "all" and not target.isdigit():
            await interaction.response.send_message("ใส่เลข ticket หรือคำว่า all", ephemeral=True)
            return
        label = "ทุกไม้" if target == "all" else f"ไม้ #{target}"
        if not await confirmed(interaction, f"ปิด{label}ใช่ไหม?"):
            return
        await reply_result(interaction, await bot.run_command("close", target), edit=True)

    @tree.command(name="risk", description="ตั้ง % ความเสี่ยงต่อไม้")
    @app_commands.describe(percent="0.1 ถึง 2.0")
    async def risk_cmd(interaction: discord.Interaction, percent: app_commands.Range[float, 0.1, 2.0]):
        if not await owner_only(interaction, control=True):
            return
        if not await confirmed(interaction, f"ตั้งความเสี่ยงต่อไม้เป็น {percent:.2f}% ใช่ไหม?"):
            return
        await reply_result(interaction, await bot.run_command("risk", f"{percent:.2f}"), edit=True)

    @tree.command(name="kill", description="ปิดทุกไม้และหยุด EA ทันที")
    async def kill_cmd(interaction: discord.Interaction):
        if not await owner_only(interaction, control=True):
            return
        if not await confirmed(interaction, "🛑 ปิดทุกไม้และหยุด EA ทันทีใช่ไหม?"):
            return
        await reply_result(interaction, await bot.run_command("kill"), edit=True)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    cfg = config.load()
    bot = XauBot(cfg)
    bot.run(cfg.token, log_handler=None)


if __name__ == "__main__":
    main()
