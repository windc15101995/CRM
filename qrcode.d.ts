declare module 'qrcode' { const QR: { toDataURL(text: string, options?: Record<string, unknown>): Promise<string> }; export default QR; }
