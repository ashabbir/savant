import { createTheme } from '@mui/material/styles';

export function createCompactTheme(mode: 'light' | 'dark') {
  const isDark = mode === 'dark';
  const hoverBg = isDark ? 'rgba(144,202,249,0.12)' : 'rgba(40,53,147,0.08)';

  return createTheme({
    palette: {
      mode,
      primary: { main: isDark ? '#90caf9' : '#283593' },
      background: {
        default: isDark ? '#0b1220' : '#f7f8fb',
        paper: isDark ? '#111827' : '#ffffff'
      },
      text: {
        primary: isDark ? '#f8fafc' : '#111827',
        secondary: isDark ? 'rgba(248,250,252,0.7)' : 'rgba(17,24,39,0.7)'
      }
    },
    shape: { borderRadius: 6 },
    typography: {
      // Compact baseline; keep everything on the small side
      fontSize: 11,
      h6: { fontSize: '0.90rem', fontWeight: 600 },
      subtitle1: { fontSize: '0.86rem' },
      subtitle2: { fontSize: '0.82rem' },
      body1: { fontSize: '0.82rem' },
      body2: { fontSize: '0.78rem' },
      button: { textTransform: 'none', fontSize: '0.74rem' },
      caption: { fontSize: '0.68rem' },
      overline: { fontSize: '0.66rem' }
    },
    components: {
      MuiCssBaseline: {
        styleOverrides: {
          body: { letterSpacing: 0.1 },
          // Hide Mermaid runtime error overlays globally to avoid noisy UI
          '.mermaid .error-icon': { display: 'none !important' as any },
          '.mermaid .error-text': { display: 'none !important' as any },
          '.mermaid .error': { display: 'none !important' as any },
          '.mermaid [class*="error"]': { display: 'none !important' as any },
          'text.error-text': { display: 'none !important' as any },
        }
      },
      MuiButton: {
        defaultProps: { size: 'small', color: 'primary' },
        styleOverrides: {
          root: { padding: '4px 10px', minHeight: 28, borderRadius: 6 },
          startIcon: { marginRight: 6, '& > *:nth-of-type(1)': { fontSize: 18 } },
          endIcon: { marginLeft: 6, '& > *:nth-of-type(1)': { fontSize: 18 } },
        }
      },
      MuiIconButton: {
        defaultProps: { size: 'small', color: 'default' },
        styleOverrides: { root: { padding: 4, width: 28, height: 28, borderRadius: 6 } }
      },
      MuiSvgIcon: {
        defaultProps: { fontSize: 'small' },
        styleOverrides: { root: { fontSize: 18 } }
      },
      MuiChip: {
        defaultProps: { size: 'small' },
        styleOverrides: { root: { height: 20 }, label: { paddingLeft: 6, paddingRight: 6 } }
      },
      MuiTextField: { defaultProps: { size: 'small' } },
      MuiFormControl: { defaultProps: { size: 'small' } },
      MuiSelect: {
        defaultProps: { size: 'small' },
        styleOverrides: { select: { paddingTop: 6, paddingBottom: 6 } }
      },
      MuiInputBase: { styleOverrides: { input: { paddingTop: 6, paddingBottom: 6, fontSize: '0.82rem' } } },
      MuiOutlinedInput: { styleOverrides: { input: { paddingTop: 6, paddingBottom: 6 } } },
      MuiTab: { styleOverrides: { root: { minHeight: 32, '&:hover': { backgroundColor: hoverBg } } } },
      MuiTabs: { styleOverrides: { root: { minHeight: 32 } } },
      MuiListItemButton: {
        styleOverrides: {
          root: {
            borderRadius: 6,
            paddingTop: 4,
            paddingBottom: 4,
            '&:hover': { backgroundColor: hoverBg },
            '&.Mui-selected, &.Mui-selected:hover': { backgroundColor: isDark ? 'rgba(144,202,249,0.2)' : 'rgba(40,53,147,0.12)' }
          }
        }
      },
      MuiListItemIcon: { styleOverrides: { root: { minWidth: 28 } } },
      MuiListItem: { styleOverrides: { root: { minHeight: 28 } } },
      MuiListItemText: { styleOverrides: { primary: { lineHeight: 1.2 } } },
      MuiTableRow: { styleOverrides: { root: { height: 28 } } },
      MuiTableCell: { styleOverrides: { root: { paddingTop: 6, paddingBottom: 6 } } },
      MuiLinearProgress: { styleOverrides: { root: { height: 3 } } },
      MuiPaper: { styleOverrides: { root: { padding: 8 } } }
    }
  });
}
