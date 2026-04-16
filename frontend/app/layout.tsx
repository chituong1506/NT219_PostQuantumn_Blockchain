export const metadata = {
  title: 'UIT Secure Transfer',
}

export default function RootLayout({ children }) {
  return (
    <html lang="vi">
      <head>
        {/* Dòng Cheat Code ở đây: Tải trực tiếp Tailwind bỏ qua hệ thống build */}
        <script src="https://cdn.tailwindcss.com"></script>
      </head>
      <body>{children}</body>
    </html>
  )
}