/** @type {import('next').NextConfig} */
const nextConfig = {
  webpack: (config) => {
    // Required for WalletConnect / RainbowKit
    config.externals.push("pino-pretty", "lokijs", "encoding");
    return config;
  },
};

export default nextConfig;
