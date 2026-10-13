import React from 'react';
import { createRoot } from 'react-dom/client';
import './index.css';

function App() {
  return <div className="boot">NS Music</div>;
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
