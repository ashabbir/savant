import React from 'react';
import { useNavigate } from 'react-router-dom';
import { useWorkflows, workflowDelete } from '../../api';
import { Alert, Box, Button, IconButton, LinearProgress, List, ListItem, ListItemSecondaryAction, ListItemText, Paper, Stack, Typography } from '@mui/material';
import DeleteIcon from '@mui/icons-material/Delete';
import EditIcon from '@mui/icons-material/Edit';

export default function WorkflowsList() {
  const nav = useNavigate();
  const { data, isLoading, isError, error, refetch } = useWorkflows();

  return (
    <Box>
      <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
        <Typography variant="subtitle1">Workflows</Typography>
        <Button variant="contained" onClick={() => nav('/engines/workflows/new')}>Create New Workflow</Button>
      </Stack>
      <Paper>
        {isLoading && <LinearProgress />}
        {isError && <Alert severity="error">{(error as any)?.message || 'Failed to load'}</Alert>}
        <List>
          {(data?.workflows || []).map((w) => (
            <ListItem key={w.id} divider secondaryAction={
              <ListItemSecondaryAction>
                <IconButton edge="end" onClick={() => nav(`/engines/workflows/edit/${w.id}`)} title="Edit">
                  <EditIcon fontSize="small" />
                </IconButton>
                <IconButton edge="end" onClick={async () => { await workflowDelete(w.id); refetch(); }} title="Delete">
                  <DeleteIcon fontSize="small" />
                </IconButton>
              </ListItemSecondaryAction>
            }>
              <ListItemText primary={w.id} secondary={`${w.title} — ${new Date(w.mtime).toLocaleString()}`} />
            </ListItem>
          ))}
        </List>
      </Paper>
    </Box>
  );
}

