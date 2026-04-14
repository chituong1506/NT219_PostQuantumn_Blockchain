use zkp_prover::api;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    api::start_server().await
}

