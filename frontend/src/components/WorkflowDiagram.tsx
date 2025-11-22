import React from 'react';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import IconButton from '@mui/material/IconButton';
import CloseIcon from '@mui/icons-material/Close';
import Box from '@mui/material/Box';
import Alert from '@mui/material/Alert';

interface WorkflowDiagramProps {
  open: boolean;
  onClose: () => void;
  svgContent: string;
  workflowName?: string;
}

export default function WorkflowDiagram({ open, onClose, svgContent, workflowName }: WorkflowDiagramProps) {
  return (
    <Dialog open={open} onClose={onClose} maxWidth="lg" fullWidth>
      <DialogTitle sx={{ m: 0, p: 2, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        Workflow: {workflowName || 'Diagram'}
        <IconButton aria-label="close" onClick={onClose} sx={{ color: 'grey.500' }}>
          <CloseIcon />
        </IconButton>
      </DialogTitle>
      <DialogContent dividers>
        {!svgContent ? (
          <Alert severity="warning">No diagram available</Alert>
        ) : (
          <Box
            sx={{
              display: 'flex',
              justifyContent: 'center',
              alignItems: 'center',
              minHeight: 300,
              '& svg': {
                maxWidth: '100%',
                height: 'auto',
              },
            }}
            dangerouslySetInnerHTML={{ __html: svgContent }}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}
