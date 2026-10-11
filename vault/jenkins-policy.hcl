# Jenkins อ่านได้อย่างเดียว เฉพาะ secret ของ workshop และของแต่ละ env ที่ pipeline deploy
# (งานจริงควรแยก AppRole ต่อ env เพื่อให้ job ของ dev อ่าน secret ของ prd ไม่ได้)
path "secret/data/workshop/*" {
  capabilities = ["read"]
}
path "secret/data/dev/*" {
  capabilities = ["read"]
}
path "secret/data/uat/*" {
  capabilities = ["read"]
}
path "secret/data/prd/*" {
  capabilities = ["read"]
}

# ยกเว้นโฟลเดอร์นี้: path ที่เจาะจงกว่าชนะเสมอ deny จึงทับ read ของ workshop/* ด้านบน
# ใช้สาธิต A3 ว่า Jenkins อ่าน secret ของทีมอื่นไม่ได้ (secret/workshop/restricted/dba-db)
path "secret/data/workshop/restricted/*" {
  capabilities = ["deny"]
}
