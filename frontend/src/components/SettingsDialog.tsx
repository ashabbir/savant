import React, { useEffect, useState } from 'react';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import Stack from '@mui/material/Stack';
import { loadConfig, saveConfig } from '../api';

export default function SettingsDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [baseUrl, setBaseUrl] = useState('');
  const [userId, setUserId] = useState('');

  useEffect(() => {
    if (open) {
      const cfg = loadConfig();
      setBaseUrl(cfg.baseUrl);
      setUserId(cfg.userId);
    }
  }, [open]);

  const save = () => {
    saveConfig({ baseUrl, userId });
    onClose();
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>Settings</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt: 1 }}>
          <TextField id="settings-base-url" name="baseUrl" label="Hub Base URL" value={baseUrl} onChange={(e) => setBaseUrl(e.target.value)} helperText="e.g., http://localhost:9999" />
          <TextField id="settings-user-id" name="userId" label="User ID Header" value={userId} onChange={(e) => setUserId(e.target.value)} helperText="Sent as x-savant-user-id" />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" onClick={save}>Save</Button>
      </DialogActions>
    </Dialog>
  );
}
