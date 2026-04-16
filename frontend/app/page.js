'use client';
import { useState } from 'react';
// import { ethers } from 'ethers'; // Sẽ dùng ở tuần sau

export default function TransferPage() {
  const [receiver, setReceiver] = useState('');
  const [amount, setAmount] = useState('');
  const [status, setStatus] = useState('Chưa giao dịch');
  const [isLoading, setIsLoading] = useState(false);

  // Hàm xử lý khi bấm nút "Chuyển Tiền"
  const handleTransfer = async (e) => {
    e.preventDefault();
    setIsLoading(true);

    try {
      // ---------------------------------------------------------
      // BƯỚC 1: XIN CHỮ KÝ PQC (Gọi sang cổng 8080)
      // ---------------------------------------------------------
      setStatus('Đang xin chữ ký Lượng tử (Dilithium)...');
      // const pqcRes = await axios.post('http://localhost:8080/sign', { data: amount });
      // const pqcSignature = pqcRes.data.signature;
      await new Promise((r) => setTimeout(r, 1000)); // Giả lập chờ 1s
      const mockPQCSig = "0xPQC_DILITHIUM_SIGNATURE_MOCK";

      // ---------------------------------------------------------
      // BƯỚC 2: XIN BẰNG CHỨNG ZKP (Gọi sang cổng 8081)
      // ---------------------------------------------------------
      setStatus('Đang tạo bằng chứng ẩn danh ZKP (STARK)...');
      // const zkpRes = await axios.post('http://localhost:8081/prove', { amount: amount });
      // const zkpProof = zkpRes.data.proof;
      await new Promise((r) => setTimeout(r, 1000)); // Giả lập chờ 1s
      const mockZKPProof = "0xZKP_STARK_PROOF_MOCK";

      // ---------------------------------------------------------
      // BƯỚC 3: ĐẨY LÊN BLOCKCHAIN BESU
      // ---------------------------------------------------------
      setStatus('Đang gửi giao dịch lên mạng Besu...');
      // Code kết nối Smart Contract bằng ethers.js sẽ nằm ở đây
      await new Promise((r) => setTimeout(r, 1500)); // Giả lập chờ 1.5s

      setStatus('✅ Giao dịch thành công!');
      alert(`Đã chuyển ${amount} ETH tới ${receiver} an toàn!`);
      
    } catch (error) {
      console.error(error);
      setStatus('❌ Giao dịch thất bại!');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-900 text-white flex flex-col items-center justify-center p-4">
      <div className="bg-gray-800 p-8 rounded-xl shadow-2xl w-full max-w-md border border-gray-700">
        <h1 className="text-2xl font-bold mb-6 text-center text-blue-400">
          UIT Secure Transfer
        </h1>
        
        <form onSubmit={handleTransfer} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-400 mb-1">Địa chỉ người nhận</label>
            <input 
              type="text" 
              value={receiver}
              onChange={(e) => setReceiver(e.target.value)}
              className="w-full px-4 py-2 bg-gray-700 border border-gray-600 rounded focus:outline-none focus:border-blue-500"
              placeholder="0x..." 
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-400 mb-1">Số lượng chuyển</label>
            <input 
              type="number" 
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="w-full px-4 py-2 bg-gray-700 border border-gray-600 rounded focus:outline-none focus:border-blue-500"
              placeholder="VD: 100" 
              required
            />
          </div>

          <button 
            type="submit" 
            disabled={isLoading}
            className={`w-full py-3 rounded font-bold transition-colors ${
              isLoading ? 'bg-gray-600 cursor-not-allowed' : 'bg-blue-600 hover:bg-blue-500'
            }`}
          >
            {isLoading ? 'Đang xử lý...' : 'Chuyển tiền bảo mật'}
          </button>
        </form>

        <div className="mt-6 p-4 bg-gray-900 rounded border border-gray-700">
          <p className="text-sm text-gray-400">Trạng thái hệ thống:</p>
          <p className={`text-sm font-mono mt-1 ${status.includes('❌') ? 'text-red-400' : 'text-green-400'}`}>
            {status}
          </p>
        </div>
      </div>
    </div>
  );
}