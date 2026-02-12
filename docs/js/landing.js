(function () {
  'use strict';

  var CMD_UNIX = 'git clone https://github.com/Zixir-lang/Zixir.git && cd Zixir && git checkout v7.1.0 && mix deps.get && mix zig.get && mix compile';
  var CMD_WIN = 'git clone https://github.com/Zixir-lang/Zixir.git; cd Zixir; git checkout v7.1.0; mix deps.get; mix zig.get; mix compile';

  function byId(id) {
    return document.getElementById(id);
  }

  function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand('copy');
      return Promise.resolve();
    } finally {
      document.body.removeChild(ta);
    }
  }

  function initCopyButton() {
    var codeEl = byId('install-code');
    var btn = byId('install-copy');
    if (!codeEl || !btn) return;
    btn.addEventListener('click', function () {
      var text = codeEl.textContent;
      copyToClipboard(text).then(function () {
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(function () {
          btn.textContent = 'Copy';
          btn.classList.remove('copied');
        }, 2000);
      });
    });
  }

  function initOsTabs() {
    var codeEl = byId('install-code');
    var unixBtn = byId('tab-unix');
    var winBtn = byId('tab-win');
    if (!codeEl || !unixBtn || !winBtn) return;
    unixBtn.addEventListener('click', function () {
      codeEl.textContent = CMD_UNIX;
      unixBtn.classList.add('active');
      winBtn.classList.remove('active');
    });
    winBtn.addEventListener('click', function () {
      codeEl.textContent = CMD_WIN;
      winBtn.classList.add('active');
      unixBtn.classList.remove('active');
    });
  }

  function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(function (a) {
      var id = a.getAttribute('href');
      if (id === '#') return;
      a.addEventListener('click', function (e) {
        var target = document.querySelector(id);
        if (target) {
          e.preventDefault();
          target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }

  function run() {
    initCopyButton();
    initOsTabs();
    initSmoothScroll();
  }
})();
