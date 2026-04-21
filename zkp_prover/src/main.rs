use axum::{
    routing::{get, post},
    http::StatusCode,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use std::net::SocketAddr;
use std::time::{SystemTime, UNIX_EPOCH};

// 1. Cục dữ liệu Web sẽ gửi sang (Có chứa Số dư thật - Bí mật quốc gia)
#[derive(Deserialize)]
struct ProveRequest {
    sender: String,
    actual_balance: u64,     // Ví dụ: 500đ
    transfer_amount: u64,    // Ví dụ: 100đ
}

// 2. Cục dữ liệu trả về Web (TUYỆT ĐỐI KHÔNG CHỨA actual_balance)
#[derive(Serialize)]
struct ProveResponse {
    status: String,
    is_valid: bool,
    zk_proof: String,
    message: String,
}

#[tokio::main]
async fn main() {
    // Khởi tạo các đường ống API
    let app = Router::new()
        .route("/", get(|| async { "🚀 Cổng tàng hình ZKP Prover đang chạy ngon lành!" }))
        .route("/api/prove", post(generate_proof));

    // Mở cổng 8081
    let addr = SocketAddr::from(([0, 0, 0, 0], 8081));
    println!("🔥 Server Rust ZKP đang lắng nghe tại http://{}", addr);

    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

// Hàm lõi: Nơi phép màu ZKP diễn ra
async fn generate_proof(Json(payload): Json<ProveRequest>) -> (StatusCode, Json<ProveResponse>) {
    
    // BƯỚC QUAN TRỌNG NHẤT: Kiểm tra xem người này có đang "chém gió" không?
    if payload.actual_balance >= payload.transfer_amount {
        
        // Nếu đủ tiền -> Giả lập quá trình tạo bằng chứng STARK phức tạp
        // Thay vì lộ số 500đ ra ngoài, ta băm nó nát bét thành một mã Hash
        let mut hasher = Sha256::new();
        let timestamp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis();
        
        // Trộn thông tin bí mật lại
        let secret_data = format!("{}_{}_{}", payload.sender, payload.actual_balance, timestamp);
        hasher.update(secret_data.as_bytes());
        
        // Sinh ra Bằng chứng
        let result = hasher.finalize();
        let mock_stark_proof = format!("0xZKP_{:x}", result); // Ép kiểu Hex

        let response = ProveResponse {
            status: "success".to_string(),
            is_valid: true,
            zk_proof: mock_stark_proof,
            message: "Tạo bằng chứng thành công: Tài khoản hợp lệ!".to_string(),
        };
        (StatusCode::OK, Json(response))
        
    } else {
        // Nếu không đủ tiền -> Từ chối tạo bằng chứng ngay lập tức
        let response = ProveResponse {
            status: "error".to_string(),
            is_valid: false,
            zk_proof: "".to_string(),
            message: "Giao dịch lừa đảo: Số dư không đủ!".to_string(),
        };
        (StatusCode::BAD_REQUEST, Json(response))
    }
}