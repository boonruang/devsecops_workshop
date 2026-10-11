storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true # workshop เท่านั้น ของจริงต้องเปิด TLS
}

api_addr      = "http://vault:8200"
ui            = true
disable_mlock = true
