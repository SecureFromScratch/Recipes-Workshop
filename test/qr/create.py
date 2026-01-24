import qrcode

payload = "sk-proj..."  
img = qrcode.make(payload)
img.save("class-qr.png")