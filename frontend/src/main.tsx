import React from 'react';
import ReactDOM from 'react-dom/client';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';

const queryClient = new QueryClient();

const basename = (import.meta.env.BASE_URL || '/').replace(/\/+$/,'');

const router = createBrowserRouter(
  [
    // Defer all routing to <App/> which declares the actual Routes
    { path: '*', element: <App /> },
  ],
  {
    basename,
    future: {
      v7_startTransition: true,
      v7_relativeSplatPath: true,
    },
  }
);

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider
        router={router}
        future={{ v7_startTransition: true, v7_relativeSplatPath: true }}
      />
    </QueryClientProvider>
  </React.StrictMode>
);
