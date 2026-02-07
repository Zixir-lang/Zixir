// Zixir Dashboard - Enhanced JavaScript

// ============================================
// Toast Notification System
// ============================================
const Toast = {
  container: null,
  
  init() {
    this.container = document.getElementById('toast-container');
    if (!this.container) {
      this.container = document.createElement('div');
      this.container.id = 'toast-container';
      this.container.className = 'toast-container';
      document.body.appendChild(this.container);
    }
  },
  
  show(message, type = 'info', duration = 4000) {
    if (!this.container) this.init();
    
    const icons = {
      success: '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>',
      error: '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>',
      warning: '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>',
      info: '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>'
    };
    
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `${icons[type] || icons.info}<span>${message}</span>`;
    
    this.container.appendChild(toast);
    
    setTimeout(() => {
      toast.classList.add('fade-out');
      setTimeout(() => toast.remove(), 300);
    }, duration);
  },
  
  success(message) { this.show(message, 'success'); },
  error(message) { this.show(message, 'error'); },
  warning(message) { this.show(message, 'warning'); },
  info(message) { this.show(message, 'info'); }
};

// ============================================
// Confirmation Dialog System
// ============================================
const Dialog = {
  overlay: null,
  titleEl: null,
  messageEl: null,
  confirmBtn: null,
  onConfirm: null,
  
  init() {
    this.overlay = document.getElementById('confirm-dialog');
    if (this.overlay) {
      this.titleEl = document.getElementById('dialog-title');
      this.messageEl = document.getElementById('dialog-message');
      this.confirmBtn = document.getElementById('dialog-confirm-btn');
      
      this.confirmBtn?.addEventListener('click', () => {
        if (this.onConfirm) {
          this.onConfirm();
          this.onConfirm = null;
        }
        this.hide();
      });
    }
  },
  
  show(title, message, onConfirm, confirmText = 'Confirm', danger = true) {
    if (!this.overlay) this.init();
    
    this.titleEl.textContent = title;
    this.messageEl.textContent = message;
    this.confirmBtn.textContent = confirmText;
    this.confirmBtn.className = danger 
      ? 'px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg transition-colors'
      : 'px-4 py-2 bg-zixir-600 hover:bg-zixir-500 text-white rounded-lg transition-colors';
    this.onConfirm = onConfirm;
    
    this.overlay.style.display = 'flex';
    setTimeout(() => this.overlay.classList.add('show'), 10);
  },
  
  hide() {
    this.overlay?.classList.remove('show');
    setTimeout(() => {
      this.overlay.style.display = 'none';
    }, 200);
  }
};

function closeDialog() {
  Dialog.hide();
}

// ============================================
// Active Navigation Highlighting
// ============================================
const Navigation = {
  init() {
    const currentPath = window.location.pathname;
    const navLinks = document.querySelectorAll('.nav-link');
    
    navLinks.forEach(link => {
      const href = link.getAttribute('href');
      if (href === currentPath || (href !== '/' && currentPath.startsWith(href))) {
        link.classList.add('active');
      } else {
        link.classList.remove('active');
      }
    });
  }
};

// ============================================
// Keyboard Shortcuts
// ============================================
const Shortcuts = {
  init() {
    document.addEventListener('keydown', (e) => {
      // Ctrl/Cmd + K for search
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        const searchInput = document.getElementById('global-search');
        if (searchInput) {
          searchInput.focus();
          searchInput.select();
        }
      }
      
      // Escape to close modals/dialogs
      if (e.key === 'Escape') {
        closeDialog();
        hideModal();
      }
      
      // Ctrl/Cmd + R to refresh current page data
      if ((e.ctrlKey || e.metaKey) && e.key === 'r') {
        // Let default refresh happen, but trigger HTMX refresh too
        document.querySelectorAll('[hx-trigger*="load"]').forEach(el => {
          htmx.trigger(el, 'refresh');
        });
      }
    });
  }
};

// ============================================
// Search/Filter System
// ============================================
const Search = {
  init() {
    const searchInputs = document.querySelectorAll('.search-input');
    
    searchInputs.forEach(input => {
      const target = input.getAttribute('data-search-target');
      if (!target) return;
      
      input.addEventListener('input', (e) => {
        const query = e.target.value.toLowerCase();
        const rows = document.querySelectorAll(`${target} tbody tr`);
        
        rows.forEach(row => {
          const text = row.textContent.toLowerCase();
          row.style.display = text.includes(query) ? '' : 'none';
        });
      });
    });
  }
};

// ============================================
// Loading States
// ============================================
const Loading = {
  show(element, message = 'Loading...') {
    element.classList.add('loading-overlay');
    element.setAttribute('data-loading-message', message);
  },
  
  hide(element) {
    element.classList.remove('loading-overlay');
  },
  
  button(btn, loading = true) {
    if (loading) {
      btn.classList.add('btn-loading');
      btn.disabled = true;
    } else {
      btn.classList.remove('btn-loading');
      btn.disabled = false;
    }
  }
};

// ============================================
// Modal Functions
// ============================================
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

// ============================================
// HTMX Event Handlers
// ============================================
document.addEventListener('htmx:afterSettle', function(e) {
  // Handle modal show after HTMX content is loaded
  if (e.detail.target.id === 'modal-content') {
    showModal();
  }
  
  // Re-initialize search after content loads
  Search.init();
});

document.addEventListener('htmx:beforeRequest', function(e) {
  // Add loading state to buttons
  const btn = e.detail.elt.closest('button');
  if (btn) {
    Loading.button(btn, true);
  }
});

document.addEventListener('htmx:afterRequest', function(e) {
  // Remove loading state from buttons
  const btn = e.detail.elt.closest('button');
  if (btn) {
    Loading.button(btn, false);
  }
  
  // Show toast on successful actions
  if (e.detail.successful) {
    const method = e.detail.elt.getAttribute('hx-post') ? 'POST' : 
                   e.detail.elt.getAttribute('hx-delete') ? 'DELETE' : 'GET';
    
    if (method === 'POST' && e.detail.elt.getAttribute('hx-post')?.includes('start')) {
      Toast.success('Workflow started successfully');
    } else if (method === 'POST' && e.detail.elt.getAttribute('hx-post')?.includes('stop')) {
      Toast.warning('Workflow stopped');
    } else if (method === 'DELETE') {
      Toast.success('Item deleted successfully');
    }
  }
});

document.addEventListener('htmx:responseError', function(e) {
  Toast.error('An error occurred. Please try again.');
});

// ============================================
// Workflow Actions with Confirmation
// ============================================
function startWorkflow(id) {
  Dialog.show(
    'Start Workflow',
    'Are you sure you want to start this workflow?',
    () => {
      htmx.ajax('POST', `/api/workflow/${id}/start`)
        .then(() => {
          Toast.success('Workflow started');
          htmx.ajax('GET', '/api/workflows/fragment', '#workflows-list');
        })
        .catch(() => {
          Toast.error('Failed to start workflow');
        });
    },
    'Start',
    false
  );
}

function stopWorkflow(id) {
  Dialog.show(
    'Stop Workflow',
    'Are you sure you want to stop this workflow? This action cannot be undone.',
    () => {
      htmx.ajax('POST', `/api/workflow/${id}/stop`)
        .then(() => {
          Toast.warning('Workflow stopped');
          htmx.ajax('GET', '/api/workflows/fragment', '#workflows-list');
        })
        .catch(() => {
          Toast.error('Failed to stop workflow');
        });
    },
    'Stop',
    true
  );
}

function retryWorkflow(id) {
  htmx.ajax('POST', `/api/workflow/${id}/retry`)
    .then(() => {
      Toast.success('Workflow retry initiated');
      htmx.ajax('GET', '/api/workflows/fragment', '#workflows-list');
    })
    .catch(() => {
      Toast.error('Failed to retry workflow');
    });
}

function deleteWorkflow(id) {
  Dialog.show(
    'Delete Workflow',
    'Are you sure you want to delete this workflow? This action cannot be undone.',
    () => {
      htmx.ajax('DELETE', `/api/workflow/${id}`)
        .then(() => {
          Toast.success('Workflow deleted');
          htmx.ajax('GET', '/api/workflows/fragment', '#workflows-list');
        })
        .catch(() => {
          Toast.error('Failed to delete workflow');
        });
    },
    'Delete',
    true
  );
}

// ============================================
// Connection Actions
// ============================================
function testConnection(id) {
  const btn = document.querySelector(`button[data-connection-id="${id}"]`);
  if (btn) Loading.button(btn, true);
  
  htmx.ajax('POST', '/api/connection/test')
    .then(() => {
      Toast.success('Connection test successful');
      htmx.ajax('GET', '/api/connections/fragment', '#connections-list');
    })
    .catch(() => {
      Toast.error('Connection test failed');
    })
    .finally(() => {
      if (btn) Loading.button(btn, false);
    });
}

function deleteConnection(id) {
  Dialog.show(
    'Delete Connection',
    'Are you sure you want to delete this connection? This action cannot be undone.',
    () => {
      htmx.ajax('DELETE', `/api/connection/${id}`)
        .then(() => {
          Toast.success('Connection deleted');
          htmx.ajax('GET', '/api/connections/fragment', '#connections-list');
        })
        .catch(() => {
          Toast.error('Failed to delete connection');
        });
    },
    'Delete',
    true
  );
}

// ============================================
// Utility Functions
// ============================================
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

function formatRelativeTime(dateString) {
  if (!dateString) return '--';
  const date = new Date(dateString);
  const now = new Date();
  const diff = now - date;
  
  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);
  
  if (seconds < 60) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (hours < 24) return `${hours}h ago`;
  if (days < 7) return `${days}d ago`;
  return date.toLocaleDateString();
}

// ============================================
// Inline Editing
// ============================================
function enableInlineEdit(element, field, id, updateUrl) {
  const originalValue = element.textContent;
  const input = document.createElement('input');
  input.type = 'text';
  input.value = originalValue;
  input.className = 'inline-edit';
  
  element.replaceWith(input);
  input.focus();
  
  function save() {
    const newValue = input.value.trim();
    if (newValue !== originalValue) {
      htmx.ajax('PATCH', `${updateUrl}/${id}`, { 
        values: { [field]: newValue }
      })
      .then(() => {
        Toast.success('Updated successfully');
      })
      .catch(() => {
        Toast.error('Failed to update');
        input.value = originalValue;
      });
    }
    
    const span = document.createElement('span');
    span.textContent = newValue || originalValue;
    span.onclick = () => enableInlineEdit(span, field, id, updateUrl);
    input.replaceWith(span);
  }
  
  input.addEventListener('blur', save);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      input.blur();
    } else if (e.key === 'Escape') {
      input.value = originalValue;
      input.blur();
    }
  });
}

// ============================================
// Initialization
// ============================================
document.addEventListener('DOMContentLoaded', function() {
  // Initialize all systems
  Toast.init();
  Dialog.init();
  Navigation.init();
  Shortcuts.init();
  Search.init();
  
  // Close modal on background click
  const modal = document.getElementById('modal');
  if (modal) {
    modal.addEventListener('click', function(e) {
      if (e.target === this) {
        hideModal();
      }
    });
  }
  
  // Add tooltip to elements with data-tooltip
  document.querySelectorAll('[data-tooltip]').forEach(el => {
    el.classList.add('tooltip');
  });
  
  console.log('🚀 Zixir Dashboard initialized');
});
