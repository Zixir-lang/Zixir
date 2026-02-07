// Zixir Dashboard JavaScript

// Modal functions
function showModal() {
  const modal = document.getElementById('modal');
  if (modal) {
    modal.classList.remove('hidden');
    modal.classList.add('flex');
    document.body.style.overflow = 'hidden';
  }
}

function hideModal() {
  const modal = document.getElementById('modal');
  const modalContent = document.getElementById('modal-content');
  if (modal) {
    modal.classList.add('hidden');
    modal.classList.remove('flex');
    document.body.style.overflow = '';
  }
  if (modalContent) {
    modalContent.innerHTML = '';
  }
}

// Close modal on background click
document.addEventListener('DOMContentLoaded', function() {
  const modal = document.getElementById('modal');
  if (modal) {
    modal.addEventListener('click', function(e) {
      if (e.target === this) {
        hideModal();
      }
    });
  }
});

// Close modal on Escape key
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') {
    hideModal();
  }
});

// HTMX event handlers
document.addEventListener('htmx:afterSettle', function(e) {
  // Handle modal show after HTMX content is loaded
  if (e.detail.target.id === 'modal-content') {
    showModal();
  }
});

document.addEventListener('htmx:beforeRequest', function(e) {
  // Show loading indicator if needed
});

document.addEventListener('htmx:afterRequest', function(e) {
  // Hide loading indicator if needed
});

// Notification system
function showNotification(message, type = 'info') {
  const notification = document.createElement('div');
  notification.className = `notification notification-${type} fixed top-4 right-4 z-50 px-4 py-3 rounded-lg shadow-lg`;
  
  const colors = {
    info: 'bg-blue-500 text-white',
    success: 'bg-emerald-500 text-white',
    warning: 'bg-yellow-500 text-black',
    error: 'bg-red-500 text-white'
  };
  
  notification.classList.add(colors[type] || colors.info);
  notification.textContent = message;
  
  document.body.appendChild(notification);
  
  setTimeout(() => {
    notification.classList.add('opacity-0', 'transition-opacity', 'duration-300');
    setTimeout(() => notification.remove(), 300);
  }, 3000);
}

// Auto-refresh status indicator
let refreshTimers = {};

function registerRefreshIndicator(elementId, interval) {
  const element = document.getElementById(elementId);
  if (element) {
    let countdown = interval;
    refreshTimers[elementId] = setInterval(() => {
      countdown -= 1;
      if (countdown <= 0) {
        countdown = interval;
      }
    }, 1000);
  }
}

// Utility functions
function formatBytes(bytes, decimals = 2) {
  if (bytes === 0) return '0 Bytes';
  
  const k = 1024;
  const dm = decimals < 0 ? 0 : decimals;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  
  return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

function formatDuration(ms) {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  if (ms < 3600000) return `${(ms / 60000).toFixed(1)}m`;
  return `${(ms / 3600000).toFixed(1)}h`;
}

function formatDate(dateString) {
  if (!dateString) return '--';
  const date = new Date(dateString);
  return date.toLocaleString();
}

// Workflow action handlers
function startWorkflow(id) {
  htmx.ajax('POST', `/api/workflow/${id}/start`)
    .then(() => {
      showNotification('Workflow started', 'success');
      htmx.ajax('GET', '/api/workflows/fragment', '#workflows-list');
    })
    .catch(() => {
      showNotification('Failed to start workflow', 'error');
    });
}

function stopWorkflow(id) {
  htmx.ajax('POST', `/api/workflow/${id}/stop`)
    .then(() => {
      showNotification('Workflow stopped', 'warning');
      htmx.ajax('GET', '/api/workflows/fragment', '#workflows-list');
    })
    .catch(() => {
      showNotification('Failed to stop workflow', 'error');
    });
}

function retryWorkflow(id) {
  htmx.ajax('POST', `/api/workflow/${id}/retry`)
    .then(() => {
      showNotification('Workflow retry initiated', 'info');
      htmx.ajax('GET', '/api/workflows/fragment', '#workflows-list');
    })
    .catch(() => {
      showNotification('Failed to retry workflow', 'error');
    });
}

// Connection action handlers
function testConnection(id) {
  htmx.ajax('POST', '/api/connection/test')
    .then(() => {
      showNotification('Connection successful', 'success');
      htmx.ajax('GET', '/api/connections/fragment', '#connections-list');
    })
    .catch(() => {
      showNotification('Connection test failed', 'error');
    });
}
