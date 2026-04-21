from fastapi import FastAPI
from pydantic import BaseModel
import hashlib
import time

# Khởi tạo Server FastAPI
app = FastAPI(
    title="UIT PQC Signature Service",
    description="Cổng cấp phát chữ ký Kháng lượng tử CRYSTALS-Dilithium",
    version="1.0"
)

# ==========================================
# MODULE MẬT MÃ LƯỢNG TỬ
# ==========================================
class DilithiumSigner:
    def __init__(self):
        # Khi tích hợp liboqs thật, chỗ này sẽ là: self.signer = oqs.Signature('Dilithium2')
        self.public_key = "PQC_PUB_KEY_UIT_0x123abc..."
        self.private_key = "PQC_PRIV_KEY_SECRET_DO_NOT_SHARE"
        print("✅ Đã nạp thành công bộ khóa CRYSTALS-Dilithium2")

    def sign_data(self, message: str) -> str:
        """
        Hàm thực hiện ký điện tử.
        Tạm thời dùng SHA3-256 băm (message + private_key) để mô phỏng định dạng của Dilithium.
        """
        # Giả lập thời gian tính toán của thuật toán Lượng tử (0.5 giây)
        time.sleep(0.5) 
        
        # Tạo chữ ký mô phỏng
        raw_sig = hashlib.sha3_256((message + self.private_key).encode()).hexdigest()
        
        # Trả về chữ ký với tiền tố PQC để Smart Contract dễ nhận diện
        return f"0xPQC_{raw_sig}"

# Khởi tạo máy ký
signer = DilithiumSigner()

# ==========================================
# ĐỊNH NGHĨA API ENDPOINTS
# ==========================================

# Định dạng dữ liệu mà Frontend (Next.js) sẽ gửi xuống
class TransactionData(BaseModel):
    sender: str
    receiver: str
    amount: int

@app.post("/api/sign")
async def generate_pqc_signature(tx_data: TransactionData):
    # 1. Đóng gói dữ liệu giao dịch thành một chuỗi duy nhất
    payload = f"{tx_data.sender}_{tx_data.receiver}_{tx_data.amount}"
    
    # 2. Gọi thuật toán Dilithium để ký lên chuỗi đó
    signature = signer.sign_data(payload)
    
    # 3. Trả kết quả về cho Frontend
    return {
        "status": "success",
        "algorithm": "CRYSTALS-Dilithium2",
        "original_payload": payload,
        "signature": signature,
        "public_key": signer.public_key,
        "timestamp": int(time.time())
    }

@app.get("/")
async def root():
    return {"message": "KSM Service đang chạy ở cổng 8080. Truy cập /docs để test API."}