# XauScalper: EA เทรด XAUUSD + Discord bot

ระบบเทรดทองคำแบบ Trend-following (breakout บน M15 ตามเทรนด์รายวัน) บน MetaTrader 5 พร้อม Discord bot สำหรับดูสถานะ สั่งหยุด และรับแจ้งเตือน

> **คำเตือน:** การเทรดทองคำด้วย leverage มีความเสี่ยงสูง อาจขาดทุนเร็วกว่าที่คาด ผล backtest และบัญชีทดลองไม่รับประกันผลบัญชีจริง ใช้บัญชี Demo จนกว่าระบบจะนิ่ง และใช้เฉพาะเงินที่เสียได้

---

## สิ่งที่ทำเสร็จแล้ว

| ส่วน | ไฟล์ | ทำอะไร |
| --- | --- | --- |
| EA หลัก | `MQL5/Experts/XauScalper/XauScalper.mq5` | รวมทุกโมดูล ตัดสินใจเข้าไม้ทุกแท่ง M15 ใหม่ |
| สัญญาณ | `MQL5/Include/XauScalper/Signal.mqh` | เทรดตามเทรนด์รายวัน (ราคาปิดเมื่อวานเทียบ EMA 200 บน D1) เข้าเมื่อแท่ง M15 ปิดทะลุจุดสูงสุด/ต่ำสุดของ 55 แท่งก่อนหน้า และอยู่ฝั่งเดียวกับ EMA 200 บน M15 (โหมด pullback แบบเดิมยังเลือกได้ใน Inputs) |
| ความเสี่ยง | `RiskManager.mqh` | คำนวณ lot จาก % ความเสี่ยง (ค่าเริ่มต้น 0.15%/ไม้ ต่อระบบ), ขาดทุนต่อวัน 1.5%, **drawdown สูงสุด 8% → ปิดทุกไม้และหยุด**, แพ้ติด 4 ไม้พัก 2 ชม., สูงสุด 10 ไม้/วัน |
| ฟิลเตอร์ | `Filters.mqh` | spread ไม่เกิน 60 points, เลี่ยงข่าวแรงของ USD ±30 นาที, ปิดทุกไม้วันศุกร์ 20:00 เวลา server |
| ส่งออเดอร์ | `TradeExecutor.mqh` | ส่งออเดอร์พร้อม SL/TP ฝั่งโบรกเกอร์ทุกครั้ง, retry เมื่อ requote |
| ดูแลไม้ | `PositionManager.mqh` | ปิดไม้ที่ถือเกิน 72 ชม. (breakeven และ trailing stop มีให้เปิดใช้ แต่ค่าเริ่มต้นปิดไว้) |
| ตัวเชื่อม | `Bridge.mqh` + `bot/bridge.py` | EA กับ bot คุยกันผ่านไฟล์ในโฟลเดอร์ Common\Files ของ MT5 |
| Discord bot | `bot/main.py` | คำสั่ง `/status` `/positions` `/report` `/pause` `/resume` `/close` `/risk` `/kill`, แจ้งเตือนเปิด/ปิดไม้, เตือนเมื่อ EA เงียบเกิน 2 นาที, สรุปรายวัน 23:00 |

SL = ATR(14) บน M15 × 3, ไม่มี TP (ปล่อยกำไรวิ่งจนโดน SL, ครบ 72 ชม. หรือวันศุกร์ 20:00) ค่าทั้งหมดปรับได้ในหน้าต่าง Inputs ของ EA

EA รัน 4 ระบบพร้อมกัน ระบบละ 0.15% ต่อไม้ (แต่ละระบบถือได้ทีละ 1 ไม้, magic 260501–260504):
1. Breakout M15, 55 แท่ง
2. Breakout M30, 20 แท่ง
3. Breakout H1, 20 แท่ง
4. Asian range breakout: กรอบราคา 01:00–08:00 เวลา server เข้าเมื่อแท่ง M5 ปิดทะลุกรอบครั้งแรกของวันตามเทรนด์ D1 (EMA 50) SL = ความกว้างกรอบ, TP 3R, ถือไม่เกิน 12 ชม.

ผลทดสอบใน Python ด้วยข้อมูล M1 ของ MetaQuotes-Demo (คิด spread ขั้นต่ำ ~0.36 USD): ปี 2023–2025 ประมาณ 44 ไม้/เดือน กำไร ~23%/ปี drawdown 7.3%; ปี 2026 กำไร +12.3% drawdown 4.5% ระบบ 2–4 ถูกเลือกหลังเห็นผลปี 2026 แล้ว ผลปี 2026 จึงเชื่อได้น้อยลง เพดาน drawdown ตั้งไว้ 8% ผลในอดีตไม่รับประกันอนาคต

### แผน 3 ระบบ เสี่ยง 1% (`MQL5/Profiles/Tester/XauScalper_3systems_1pct.set`)

ใช้เฉพาะระบบ 1–3 (ปิดระบบ 4) และตั้งค่าให้ตรงกับที่เทสใน Python:

- เสี่ยง 1% ต่อไม้ ต่อระบบ, แต่ละระบบถือได้ทีละ 1 ไม้
- ฝั่งเดียวกัน (buy หรือ sell) เปิดพร้อมกันได้ไม่เกิน 2 ไม้ รวมทุกระบบ (input ใหม่ `InpMaxSameSide`, ค่าเริ่มต้น 0 = ไม่จำกัด เหมือนเดิม)
- ไม่ใช้ตัวกรองข่าว และไม่พักหลังแพ้ติด (`InpMaxConsecLoss=99`) เพราะในเทสไม่มีสองกฎนี้
- ตัวหยุดฉุกเฉิน: drawdown 40% ปิดทุกไม้และหยุด (เทสเจอสูงสุด 28%), ขาดทุนต่อวัน 5% หยุดเปิดไม้ใหม่ถึงพรุ่งนี้ (วันที่แย่สุดในเทส −4.1R), สูงสุด 20 ไม้/วัน

ผลเทส ม.ค. 2023 – ต.ค. 2026 (46 เดือน, ข้อมูล M1 ของ MetaQuotes-Demo, หักต้นทุนแล้ว): 1,012 ไม้ (~22 ไม้/เดือน) ชนะ 33% ไม้ที่ชนะได้เฉลี่ย +2.5R ไม้ที่แพ้เสียเฉลี่ย −0.85R, profit factor 1.48, กำไรทบต้นเฉลี่ย ~95%/ปี, drawdown สูงสุด 28% (นับจากไม้ที่ปิดแล้ว ตอนถือไม้อยู่อาจลึกกว่านี้), แพ้ติดกันยาวสุด 24 ไม้ ถ้าเสี่ยง 2% drawdown จะขึ้นไปราว 49% ระบบและค่าต่างๆ ถูกเลือกจากผลเทสชุดเดียวกันนี้ ผลจริงน่าจะต่ำกว่านี้

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
2. Expert: `XauScalper`, Symbol: XAUUSD, Timeframe: M15
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
