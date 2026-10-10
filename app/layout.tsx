export const metadata = { title: 'Khaya Properties | Where Property Finds You', description: "South Africa's property marketplace for buyers, tenants, owners, landlords, developers and agents." };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en-ZA"><body style={{ fontFamily: 'system-ui, sans-serif', margin: 0 }}>{children}</body></html>;
}
