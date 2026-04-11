import type { Config } from "tailwindcss";
import typography from "@tailwindcss/typography";
// @ts-ignore
import rtl from "tailwindcss-rtl";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  darkMode: "class",
  theme: {
    screens: {
      xs: '480px',
      sm: '640px',
      md: '768px',
      lg: '1024px',
      xl: '1280px',
      '2xl': '1536px',
    },
    extend: {
      colors: {
        background: "var(--background)",
        foreground: "var(--foreground)",
        "nor-black": "#080808",
        "nor-green": "#00FF85",
        "nor-white": "#FFFFFF",
      },
      fontFamily: {
        amiri: ["var(--font-amiri)", "serif"],
        ibm: ["var(--font-ibm)", "sans-serif"],
        readex: ["var(--font-readex)", "sans-serif"],
        almarai: ["var(--font-almarai)", "sans-serif"],
      },
      animation: {
        "spin-slow": "spin 3s linear infinite",
        ticker: "ticker 20s linear infinite",
        pulse: "pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite",
        "slide-in-right": "slideInRight 0.5s ease-out forwards",
      },
      keyframes: {
        ticker: {
          "0%": { transform: "translateX(0)" },
          "100%": { transform: "translateX(-100%)" },
        },
        slideInRight: {
          "0%": { transform: "translateX(100%)", opacity: "0" },
          "100%": { transform: "translateX(0)", opacity: "1" },
        },
      },
    },
  },
  plugins: [typography, rtl],
};
export default config;
