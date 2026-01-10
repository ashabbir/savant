// Shim for '@mui/material/styles' to ensure `styled` comes from the system/engine
// Avoids CJS/ESM interop glitches that can yield a non-function styled_default in some bundles.

// Re-export everything from the actual styles index (bypass alias to avoid recursion)
export * from '@mui/material/styles/index.js';
// Force both named exports to resolve to the styled-engine-backed function
export { default as styled } from '@mui/system/styled';
export { default as experimentalStyled } from '@mui/system/styled';
