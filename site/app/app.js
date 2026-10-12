(function () {
  var MARK =
    '<svg viewBox="0 0 96 96" fill="none" aria-hidden="true">' +
    '<defs>' +
    '<linearGradient id="cmA" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.95"/><stop offset="1" stop-color="#bfc4d0" stop-opacity="0.55"/></linearGradient>' +
    '<linearGradient id="cmB" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e8ebf2" stop-opacity="0.8"/><stop offset="1" stop-color="#8a90a0" stop-opacity="0.4"/></linearGradient>' +
    '</defs>' +
    '<polygon points="48,6 76,34 48,52" fill="url(#cmA)"/>' +
    '<polygon points="48,6 20,34 48,52" fill="url(#cmB)"/>' +
    '<polygon points="20,34 48,52 48,90" fill="url(#cmA)" opacity="0.7"/>' +
    '<polygon points="76,34 48,52 48,90" fill="url(#cmB)" opacity="0.8"/>' +
    '<polygon points="48,6 76,34 48,52 20,34" stroke="rgba(255,255,255,0.45)" stroke-width="0.8" fill="none"/>' +
    '<polyline points="20,34 48,90 76,34" stroke="rgba(255,255,255,0.25)" stroke-width="0.8" fill="none"/>' +
    '</svg>';

  var PLATFORMS = {
    ios: {
      id: 'ios',
      name: 'iPhone',
      short: 'iOS',
      file: 'NodeShiftMusic.ipa',
      requirement: 'iOS 17 и новее',
      steps: [
        'Скачай <b>NodeShiftMusic.ipa</b> на компьютер.',
        'Поставь через <b>Sideloadly</b> или <b>AltStore</b> со своим Apple ID. Приложение приходит неподписанным, подпись ставит твой Apple ID.',
        'Включи режим разработчика: Настройки → Конфиденциальность и безопасность → Режим разработчика.',
        'Бесплатный Apple ID даёт подпись на 7 дней. Чтобы не переподписывать руками, используй <b>AltStore</b> или <b>SideStore</b>.',
        'Новые версии приложение находит само и показывает баннер «Доступно обновление».'
      ]
    },
    android: {
      id: 'android',
      name: 'Android',
      short: 'Android',
      file: 'NodeShiftMusic.apk',
      requirement: 'Android 8 и новее',
      steps: [
        'Скачай <b>NodeShiftMusic.apk</b> прямо на телефон.',
        'Разреши установку из браузера: Настройки → Приложения → Особый доступ → Установка неизвестных приложений.',
        'Открой скачанный файл и нажми «Установить». Если Play Protect спросит, выбери «Всё равно установить».',
        'Новые версии приложение находит само и показывает баннер «Доступно обновление».'
      ]
    },
    win: {
      id: 'win',
      name: 'Windows',
      short: 'Windows',
      file: 'NodeShiftMusic-Setup.exe',
      requirement: 'Windows 10 и новее',
      steps: [
        'Скачай <b>NodeShiftMusic-Setup.exe</b>.',
        'Установщик пока без подписи, поэтому SmartScreen покажет «Windows защитила ваш компьютер»: нажми «Подробнее» → «Выполнить в любом случае».',
        'Ставится в папку пользователя, права администратора не нужны.',
        'Новые версии приложение находит само и обновляется по кнопке.'
      ]
    }
  };

  var ORDER = ['ios', 'android', 'win'];

  function el(tag, props, children) {
    var node = document.createElement(tag);
    if (props) {
      Object.keys(props).forEach(function (key) {
        if (key === 'html') node.innerHTML = props[key];
        else if (key === 'text') node.textContent = props[key];
        else node.setAttribute(key, props[key]);
      });
    }
    (children || []).forEach(function (child) {
      if (child) node.appendChild(child);
    });
    return node;
  }

  function detect() {
    var ua = navigator.userAgent || '';
    if (/iPhone|iPad|iPod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) return 'ios';
    if (/Android/i.test(ua)) return 'android';
    var data = navigator.userAgentData;
    if (/Windows/i.test(ua) || (data && data.platform === 'Windows')) return 'win';
    return null;
  }

  function formatSize(bytes) {
    if (!bytes) return '';
    var mb = bytes / 1048576;
    return (mb >= 100 ? mb.toFixed(0) : mb.toFixed(1)) + ' МБ';
  }

  function formatDate(iso) {
    if (!iso) return '';
    var date = new Date(iso);
    if (isNaN(date.getTime())) return '';
    return date.toLocaleString('ru-RU', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
  }

  function loadManifest(id) {
    return fetch('/app/update/files/' + id, { cache: 'no-store' })
      .then(function (response) {
        if (!response.ok) return null;
        return response.json();
      })
      .catch(function () {
        return null;
      });
  }

  function metaLine(manifest) {
    var parts = [];
    if (manifest.version) parts.push('v' + manifest.version + (manifest.build ? ' · сборка ' + manifest.build : ''));
    if (manifest.size) parts.push(formatSize(manifest.size));
    var when = formatDate(manifest.builtAt);
    if (when) parts.push(when);
    return el('div', { class: 'meta' }, parts.map(function (text) {
      return el('span', { text: text });
    }));
  }

  function mountMark() {
    var mark = document.getElementById('mark');
    if (mark) mark.innerHTML = MARK;
  }

  function renderIndex() {
    var detected = detect();
    var primary = document.getElementById('primary');
    var all = document.getElementById('all');
    Promise.all(ORDER.map(loadManifest)).then(function (manifests) {
      var byId = {};
      ORDER.forEach(function (id, index) {
        byId[id] = manifests[index];
      });
      primary.textContent = '';
      if (detected) {
        var platform = PLATFORMS[detected];
        var manifest = byId[detected];
        primary.appendChild(el('h2', { text: 'Скачать для ' + platform.name }));
        if (manifest) {
          primary.appendChild(metaLine(manifest));
          primary.appendChild(el('p', { class: 'note', text: platform.requirement + '. Откроется страница с инструкцией и кнопкой загрузки.' }));
          primary.appendChild(el('a', { class: 'btn primary', href: '/app/files/' + detected, text: 'Скачать' }));
        } else {
          primary.appendChild(el('p', { class: 'note', text: 'Сборки для ' + platform.name + ' пока нет. Страница обновится сама, когда она появится.' }));
          primary.appendChild(el('a', { class: 'btn ghost', href: '/app/files/' + detected, text: 'Открыть страницу' }));
        }
      } else {
        primary.appendChild(el('h2', { text: 'Выбери платформу' }));
        primary.appendChild(el('p', { class: 'note', text: 'Не получилось определить устройство. Выбери свою платформу ниже.' }));
      }
      all.textContent = '';
      ORDER.forEach(function (id) {
        var platform = PLATFORMS[id];
        var manifest = byId[id];
        all.appendChild(
          el('a', { class: 'tile', href: '/app/files/' + id }, [
            el('b', { text: platform.short }),
            el('span', { text: manifest ? 'v' + manifest.version + ' · ' + formatSize(manifest.size) : 'скоро' })
          ])
        );
      });
    });
  }

  function platformFromPath() {
    var match = location.pathname.match(/\/app\/files\/(ios|android|win)/);
    return match ? match[1] : null;
  }

  function renderPlatform() {
    var id = platformFromPath();
    if (!id) {
      location.replace('/app/');
      return;
    }
    var platform = PLATFORMS[id];
    document.title = 'Скачать NodeShift Music для ' + platform.name;
    document.getElementById('eyebrow').textContent = 'Скачать · ' + platform.requirement;
    document.getElementById('title').textContent = 'NodeShift Music для ' + platform.name;
    var steps = document.getElementById('steps');
    var list = el('ol', { class: 'steps' }, platform.steps.map(function (html) {
      return el('li', { html: html });
    }));
    steps.appendChild(list);
    var others = document.getElementById('others');
    ORDER.filter(function (other) {
      return other !== id;
    }).forEach(function (other) {
      others.appendChild(
        el('a', { class: 'tile', href: '/app/files/' + other }, [
          el('b', { text: PLATFORMS[other].short }),
          el('span', { text: PLATFORMS[other].requirement })
        ])
      );
    });
    var card = document.getElementById('card');
    loadManifest(id).then(function (manifest) {
      card.textContent = '';
      if (!manifest) {
        card.appendChild(el('h2', { text: 'Сборки пока нет' }));
        card.appendChild(el('p', { class: 'note', text: 'Приложение для ' + platform.name + ' ещё собирается. Заходи позже, страница сама покажет кнопку, когда файл появится.' }));
        card.appendChild(el('span', { class: 'btn primary', 'aria-disabled': 'true', text: 'Скоро' }));
        return;
      }
      card.appendChild(el('h2', { text: 'Версия ' + manifest.version }));
      card.appendChild(metaLine(manifest));
      if (manifest.notes) card.appendChild(el('p', { class: 'note', text: manifest.notes }));
      card.appendChild(el('a', { class: 'btn primary', href: '/app/files/' + id + '/download', text: 'Скачать ' + platform.file }));
      if (manifest.sha256) {
        card.appendChild(el('div', { class: 'meta hash' }, [el('span', { text: 'sha256 ' + manifest.sha256 })]));
      }
    });
  }

  mountMark();
  var page = document.querySelector('[data-page]');
  if (page && page.getAttribute('data-page') === 'index') renderIndex();
  else if (page) renderPlatform();
})();
