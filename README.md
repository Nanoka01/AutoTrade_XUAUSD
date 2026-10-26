# XauScalper: EA เทรด XAUUSD + Discord bot

ระบบ scalping ทองคำแบบ Trend-following บน MetaTrader 5 พร้อม Discord bot สำหรับดูสถานะ สั่งหยุด และรับแจ้งเตือน

> **คำเตือน:** การเทรดทองคำด้วย leverage มีความเสี่ยงสูง อาจขาดทุนเร็วกว่าที่คาด ผล backtest และบัญชีทดลองไม่รับประกันผลบัญชีจริง ใช้บัญชี Demo จนกว่าระบบจะนิ่ง และใช้เฉพาะเงินที่เสียได้

---

## สิ่งที่ทำเสร็จแล้ว

| ส่วน | ไฟล์ | ทำอะไร |
| --- | --- | --- |
| EA หลัก | `MQL5/Experts/XauScalper/XauScalper.mq5` | รวมทุกโมดูล ตัดสินใจเข้าไม้ทุกแท่ง M5 ใหม่ |
| สัญญาณ | `MQL5/Include/XauScalper/Signal.mqh` | เทรนด์จาก EMA 50/200 บน M15, เข้าเมื่อย่อตัวแตะ EMA 20 บน M5 แล้ว RSI(7) ตัด 50 กลับตามเทรนด์ |
| ความเสี่ยง | `RiskManager.mqh` | คำนวณ lot จาก % ความเสี่ยง, ขาดทุนต่อวัน 1.5%, **drawdown สูงสุด 5% → ปิดทุกไม้และหยุด**, แพ้ติด 4 ไม้พัก 2 ชม., สูงสุด 10 ไม้/วัน |
| ฟิลเตอร์ | `Filters.mqh` | spread ไม่เกิน 30 points, เทรดเฉพาะ 10:00–22:00 เวลา server, เลี่ยงข่าวแรงของ USD ±30 นาที, ปิดทุกไม้วันศุกร์ 21:00 |
| ส่งออเดอร์ | `TradeExecutor.mqh` | ส่งออเดอร์พร้อม SL/TP ฝั่งโบรกเกอร์ทุกครั้ง, retry เมื่อ requote |
| ดูแลไม้ | `PositionManager.mqh` | เลื่อน SL ไปจุดทุนที่ 0.8R, trailing stop ตาม ATR หลัง 1R |
| ตัวเชื่อม | `Bridge.mqh` + `bot/bridge.py` | EA กับ bot คุยกันผ่านไฟล์ในโฟลเดอร์ Common\Files ของ MT5 |
| Discord bot | `bot/main.py` | คำสั่ง `/status` `/positions` `/report` `/pause` `/resume` `/close` `/risk` `/kill`, แจ้งเตือนเปิด/ปิดไม้, เตือนเมื่อ EA เงียบเกิน 2 นาที, สรุปรายวัน 23:00 |

SL = ATR(14) × 1.5, TP = 1.5 เท่าของ SL ค่าทั้งหมดปรับได้ในหน้าต่าง Inputs ของ EA

---

## สิ่งที่คุณต้องทำ (ตามลำดับ)

ทั้งหมดทำบนคอมพิวเตอร์ Windows ของคุณเองได้ ยังไม่ต้องเช่า VPS

### 1. ติดตั้ง MT5 และเปิดบัญชีทดลอง

1. ดาวน์โหลด MT5 จากเว็บโบรกเกอร์ที่ตั้งใจจะใช้จริงในอนาคต (แนะนำ เพราะ spread และชื่อ symbol จะตรงกับบัญชีจริง) หรือจาก metatrader5.com
2. File → Open an Account → เลือกโบรกเกอร์ → Open a demo account ตั้งเงินทุนเท่ากับที่คิดว่าจะใช้จริง
3. ใน Market Watch คลิกขวา → Symbols → หา XAUUSD (บางโบรกชื่อ `XAUUSDm` หรือ `GOLD`) แล้วกด Show

### 2. ติดตั้ง EA

1. ใน MT5 กด File → Open Data Folder
2. คัดลอกโฟลเดอร์ `MQL5/Experts/XauScalper` ไปไว้ที่ `MQL5\Experts\`
3. คัดลอกโฟลเดอร์ `MQL5/Include/XauScalper` ไปไว้ที่ `MQL5\Include\`
4. เปิด MetaEditor (กด F4 ใน MT5) → เปิด `Experts\XauScalper\XauScalper.mq5` → กด Compile (F7)
5. ถ้ามี error ให้คัดลอกข้อความในแท็บ Errors มาส่งให้ผม ผมเขียนโค้ดนี้โดยยังไม่ได้ compile ใน MetaEditor จริง

### 3. Backtest ก่อน

1. ใน MT5 กด Ctrl+R เปิด Strategy Tester
2. Expert: `XauScalper`, Symbol: XAUUSD, Timeframe: M5
3. Modelling: **Every tick based on real ticks**, ช่วงเวลา 2–3 ปีล่าสุด, Deposit เท่าทุนที่ตั้งใจใช้
4. กด Start แล้วดูแท็บ Backtest: Profit Factor, Maximal drawdown, Total trades
5. ส่งภาพหน้าจอผลมาให้ผมดู เราจะปรับค่าด้วยกันก่อนรันบน Demo

### 4. สร้าง Discord server และ bot (ทำได้เลยตอนนี้)

1. ใน Discord กด + → Create My Own → ตั้งชื่อ server
2. สร้าง 4 ช่อง: `#control` `#trades` `#alerts` `#reports`
3. เข้า https://discord.com/developers/applications → New Application → ตั้งชื่อ
4. แท็บ Bot → Reset Token → คัดลอก token เก็บไว้ (ห้ามส่งให้ใคร รวมถึงในแชตนี้)
5. แท็บ OAuth2 → URL Generator → เลือก scope `bot` และ `applications.commands` → Bot permissions เลือก Send Messages, Embed Links, Read Message History → เปิดลิงก์ที่ได้แล้วเชิญ bot เข้า server
6. Discord Settings → Advanced → เปิด Developer Mode จากนั้นคลิกขวาที่ชื่อ server, ชื่อตัวเอง และแต่ละช่อง → Copy ID

### 5. รัน Discord bot

1. ติดตั้ง Python 3.11 ขึ้นไปจาก python.org (ติ๊ก "Add python.exe to PATH")
2. เปิด Command Prompt ในโฟลเดอร์ `bot` แล้วรัน:
   ```
   python -m venv .venv
   .venv\Scripts\activate
   pip install -r requirements.txt
   copy .env.example .env
   ```
3. เปิด `.env` ด้วย Notepad กรอก token และ ID ทั้งหมดจากขั้นตอนที่ 4
4. รัน `python main.py` ควรเห็นข้อความ "Bot ออนไลน์แล้ว" ใน `#alerts`

### 6. รันบนบัญชี Demo

1. เปิดกราฟ XAUUSD (timeframe ใดก็ได้) → ลาก XauScalper จาก Navigator ใส่กราฟ
2. แท็บ Common ติ๊ก Allow Algo Trading → OK และกดปุ่ม **Algo Trading** บนแถบเครื่องมือให้เป็นสีเขียว
3. พิมพ์ `/status` ใน `#control` ควรเห็นยอดบัญชีและสถานะ
4. ตั้งคอมไม่ให้ sleep (Settings → System → Power) ระหว่างวันจันทร์–ศุกร์ ถ้าคอมปิดหรือหลับ EA ก็หยุด แต่ไม้ที่เปิดอยู่ยังมี SL/TP ที่โบรกเกอร์
5. รันอย่างน้อย 4–8 สัปดาห์ จด/ส่งผล `/report week` ให้ผมทุกสัปดาห์

---

## คำสั่ง Discord

| คำสั่ง | ทำอะไร | ต้องกดยืนยัน |
| --- | --- | --- |
| `/status` | ยอดเงิน equity drawdown เทรนด์ spread | ไม่ |
| `/positions` | ไม้ที่เปิดอยู่ | ไม่ |
| `/report` | สรุป win rate, profit factor, กำไรสุทธิ (วัน/7 วัน/30 วัน) | ไม่ |
| `/pause` | หยุดเปิดไม้ใหม่ ไม้เดิมยังดูแลต่อ | ไม่ |
| `/resume` | กลับมาเทรด | ใช่ |
| `/close` | ปิดไม้ตาม ticket หรือ `all` | ใช่ |
| `/risk` | ตั้ง % ความเสี่ยงต่อไม้ (0.1–2.0) | ใช่ |
| `/kill` | ปิดทุกไม้และหยุด EA | ใช่ |

คำสั่งควบคุมใช้ได้เฉพาะเจ้าของ (OWNER_ID) และเฉพาะในช่อง `#control`

## เมื่อพร้อมย้ายไปบัญชีจริง

- ตอนนั้นค่อยพิจารณา Windows VPS (ราว 10–20 USD/เดือน) เพื่อให้รัน 24 ชม. ไม่ขึ้นกับคอมที่บ้าน
- เริ่มด้วย `/risk 0.25` และเปิด HEALTHCHECK_URL (Healthchecks.io ฟรี) เพื่อรู้ตัวเมื่อเครื่องดับทั้งเครื่อง
