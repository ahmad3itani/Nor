export default function Footer() {
  return (
    <footer className="border-t border-neutral-800 py-8 bg-nor-black">
      <div className="container mx-auto px-4 text-center">
        <p className="text-sm text-neutral-500 font-readex" suppressHydrationWarning>
          © {new Date().getFullYear()} Goaliador.com | المنصة الآلية للصحافة الرياضية العربية
        </p>
      </div>
    </footer>
  );
}
