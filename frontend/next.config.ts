/** @type {import('next').NextConfig} */
const nextConfig = {
  // Ép Next.js chỉ hoạt động đúng trong thư mục frontend
  outputFileTracingRoot: process.cwd(),
};

export default nextConfig;
