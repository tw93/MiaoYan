// Slides get no note HTML from the app: reveal renders the raw markdown in
// the page, so PreviewMedia.relayedYouTubeFrames never sees their iframes,
// and a YouTube frame on a local page shows Error 153 (no Referer). This
// sends each one through the same relay, with the same id and start rules
// as PreviewMedia.youTubeVideo. Only real iframes are touched: an iframe in
// a code fence is rendered as text.
(function (root) {
  var relay = 'https://cdn.miaoyan.app/Resources/DownView.bundle/youtube.html';

  // `90`, `90s` or `1h2m3s`; nine characters at most.
  function seconds (time) {
    if (time.length > 9) return null;
    if (/^[+-]?\d+$/.test(time)) {
      var plain = parseInt(time, 10);
      return plain > 0 ? plain : null;
    }
    if (!time || !/^(\d+h)?(\d+m)?(\d+s)?$/.test(time)) return null;
    var total = 0;
    var number = 0;
    for (var i = 0; i < time.length; i++) {
      var character = time[i];
      if (character >= '0' && character <= '9') {
        number = number * 10 + (character.charCodeAt(0) - 48);
        continue;
      }
      total += number * (character === 'h' ? 3600 : character === 'm' ? 60 : 1);
      number = 0;
    }
    return total > 0 ? total : null;
  }

  function video (address) {
    if (typeof address !== 'string') return null;
    address = address.trim().split('&amp;').join('&');
    if (address.indexOf('//') === 0) address = 'https:' + address;
    var parts;
    try {
      parts = new URL(address);
    } catch (error) {
      return null;
    }
    var host = parts.hostname.toLowerCase();
    if (!host) return null;
    var site = host.indexOf('www.') === 0 || host.indexOf('m.') === 0 ? host.slice(host.indexOf('.') + 1) : host;
    var path = parts.pathname.split('/').filter(function (segment) { return segment.length > 0; });
    var query = [];
    parts.searchParams.forEach(function (value, name) { query.push([name, value]); });
    function first (names) {
      for (var i = 0; i < query.length; i++) {
        if (names.indexOf(query[i][0]) !== -1) return query[i][1];
      }
      return null;
    }
    var id = null;
    if (site === 'youtu.be') {
      id = path[0] || null;
    } else if (site === 'youtube.com' || site === 'youtube-nocookie.com') {
      if (path.length === 1 && path[0] === 'watch') {
        id = first(['v']);
      } else if (path.length >= 2 && ['embed', 'shorts', 'live', 'v'].indexOf(path[0]) !== -1 && ['videoseries', 'live_stream'].indexOf(path[1]) === -1) {
        id = path[1];
      }
    }
    if (!id || !/^[A-Za-z0-9_-]{11}$/.test(id)) return null;
    return { id: id, start: seconds(first(['start', 't']) || '') };
  }

  function relayed (address) {
    var found = video(address);
    if (!found) return null;
    return relay + '?v=' + found.id + (found.start ? '&start=' + found.start : '');
  }

  function relayFrame (frame) {
    ['src', 'data-src'].forEach(function (name) {
      var target = relayed(frame.getAttribute(name));
      if (target) frame.setAttribute(name, target);
    });
  }

  function relayFrames (node) {
    if (!node || node.nodeType !== 1) return;
    if (node.tagName === 'IFRAME') relayFrame(node);
    var frames = node.getElementsByTagName ? node.getElementsByTagName('iframe') : [];
    for (var i = 0; i < frames.length; i++) relayFrame(frames[i]);
  }

  // Reveal builds the slides after this runs, moves them into print pages
  // for a PDF, and sets `src` again from `data-src` as slides come and go.
  function observe (target) {
    relayFrames(target);
    if (typeof MutationObserver === 'undefined') return;
    new MutationObserver(function (records) {
      records.forEach(function (record) {
        if (record.type === 'attributes') {
          relayFrames(record.target);
          return;
        }
        for (var i = 0; i < record.addedNodes.length; i++) relayFrames(record.addedNodes[i]);
      });
    }).observe(target, { childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'data-src'] });
  }

  root.MiaoYanYouTubeRelay = { relay: relay, video: video, relayed: relayed, relayFrames: relayFrames, observe: observe };
})(typeof window !== 'undefined' ? window : this);
