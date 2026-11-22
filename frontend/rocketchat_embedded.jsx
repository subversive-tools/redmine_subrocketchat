import React, { useState, useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import { EmbeddedChat, useMessageStore } from '@embeddedchat/react';

// Expose message store globally so Redmine buttons can open/close threads directly
window.RedmineRocketChatStore = useMessageStore;

// Strip markdown, links, emojis, and second-line metadata from thread titles so only "#123: Ticket Subject" is shown
window.__rcFormatThreadTitle = function (rawMsg) {
  if (!rawMsg) return '';
  const firstLine = String(rawMsg).split(/\r?\n/)[0];
  return firstLine
    .replace(/🎫/g, '')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[*_~`>]/g, '')
    .trim();
};

window.__rcOpenFullClient = function () {
  const w = window.__rcPrimaryWidget;
  if (w && w.rcUrl && w.channelName) {
    window.open(`${w.rcUrl}/group/${w.channelName}`, '_blank', 'noopener,noreferrer');
  }
};

function installRocketChatFetchProxy(rcHost, proxyBaseUrl) {
  if (!rcHost || !proxyBaseUrl) return;
  window.__rcProxyBaseUrl = proxyBaseUrl;
  window.__rcCleanHost = rcHost.replace(/\/$/, '');

  if (window.__rcFetchProxyInstalled) return;
  window.__rcFetchProxyInstalled = true;

  const origFetch = window.fetch.bind(window);

  window.fetch = function (input, init = {}) {
    let urlStr = typeof input === 'string' ? input : input?.url || '';
    const cleanHost = window.__rcCleanHost;
    const currentProxyBase = window.__rcProxyBaseUrl;
    if (cleanHost && currentProxyBase && urlStr.startsWith(cleanHost + '/api/')) {
      const relativePath = urlStr.slice(cleanHost.length + 1); // e.g. "api/v1/login"
      const proxiedUrl = `${currentProxyBase}/${relativePath}`;
      return origFetch(proxiedUrl, {
        ...init,
        credentials: 'same-origin',
      });
    }
    return origFetch(input, init);
  };
}

function buildRedmineAdaptiveTheme() {
  const bodyStyle = window.getComputedStyle(document.body);
  const contentEl = document.getElementById('content') || document.body;
  const contentStyle = window.getComputedStyle(contentEl);
  const topMenuEl = document.getElementById('top-menu');
  const selectedTabEl = document.querySelector('#main-menu li a.selected');
  const linkEl = document.querySelector('#content a') || document.querySelector('a');
  const boxEl = document.querySelector('.box');

  const fontFamily =
    bodyStyle.fontFamily ||
    '"Source Sans Pro", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
  const fontSizePx = parseInt(bodyStyle.fontSize, 10) || 13;

  const isTransparent = (c) => !c || c === 'transparent' || c === 'rgba(0, 0, 0, 0)';

  const bg = !isTransparent(contentStyle.backgroundColor)
    ? contentStyle.backgroundColor
    : !isTransparent(bodyStyle.backgroundColor)
      ? bodyStyle.backgroundColor
      : '#ffffff';

  const fg = contentStyle.color || bodyStyle.color || '#212136';

  let primary = '#3E5B76';
  if (selectedTabEl && !isTransparent(window.getComputedStyle(selectedTabEl).backgroundColor)) {
    primary = window.getComputedStyle(selectedTabEl).backgroundColor;
  } else if (topMenuEl && !isTransparent(window.getComputedStyle(topMenuEl).backgroundColor)) {
    primary = window.getComputedStyle(topMenuEl).backgroundColor;
  } else if (linkEl && window.getComputedStyle(linkEl).color) {
    primary = window.getComputedStyle(linkEl).color;
  }

  let secondary = '#f4f6f8';
  let border = '#d8dee4';
  if (boxEl) {
    const boxStyle = window.getComputedStyle(boxEl);
    if (!isTransparent(boxStyle.backgroundColor) && boxStyle.backgroundColor !== bg) {
      secondary = boxStyle.backgroundColor;
    }
    if (!isTransparent(boxStyle.borderTopColor)) {
      border = boxStyle.borderTopColor;
    }
  }

  // Export CSS custom properties so rocketchat.css also inherits the active Redmine theme's exact palette & font
  const rootStyle = document.documentElement.style;
  const topMenuHeight = topMenuEl ? Math.round(topMenuEl.getBoundingClientRect().height) : 0;
  if (topMenuHeight >= 18) {
    rootStyle.setProperty('--rc-top-menu-height', `${topMenuHeight}px`);
  }
  rootStyle.setProperty('--rc-theme-font', fontFamily);
  rootStyle.setProperty('--rc-theme-font-size', `${fontSizePx}px`);
  rootStyle.setProperty('--rc-theme-bg', bg);
  rootStyle.setProperty('--rc-theme-fg', fg);
  rootStyle.setProperty('--rc-theme-primary', primary);
  rootStyle.setProperty('--rc-theme-secondary', secondary);
  rootStyle.setProperty('--rc-theme-border', border);

  return {
    radius: '4px',
    commonColors: {
      black: '#000000',
      white: '#ffffff',
    },
    schemes: {
      light: {
        background: bg,
        foreground: fg,
        card: bg,
        cardForeground: fg,
        popover: bg,
        popoverForeground: fg,
        primary: primary,
        primaryForeground: '#ffffff',
        secondary: secondary,
        secondaryForeground: fg,
        muted: secondary,
        mutedForeground: '#64748b',
        accent: secondary,
        accentForeground: fg,
        destructive: '#c62828',
        destructiveForeground: '#ffffff',
        border: border,
        input: border,
        ring: primary,
        warning: '#f59e0b',
        warningForeground: '#fef3c7',
        success: '#dcfce7',
        successForeground: '#166534',
        info: primary,
        infoForeground: '#ffffff',
      },
      dark: {
        background: '#1e2228',
        foreground: '#e4e7eb',
        card: '#1e2228',
        cardForeground: '#e4e7eb',
        popover: '#262b33',
        popoverForeground: '#e4e7eb',
        primary: primary,
        primaryForeground: '#ffffff',
        secondary: '#2a3038',
        secondaryForeground: '#e4e7eb',
        muted: '#2a3038',
        mutedForeground: '#94a3b8',
        accent: '#2a3038',
        accentForeground: '#e4e7eb',
        destructive: '#ef4444',
        destructiveForeground: '#ffffff',
        border: '#374151',
        input: '#374151',
        ring: primary,
        warning: '#fef3c7',
        warningForeground: '#f59e0b',
        success: '#166534',
        successForeground: '#dcfce7',
        info: primary,
        infoForeground: '#ffffff',
      },
    },
    typography: {
      default: {
        fontFamily: fontFamily,
        fontSize: fontSizePx,
        fontWeightRegular: 400,
      },
      h1: { fontSize: '1.25rem', fontWeight: 600 },
      h2: { fontSize: '1.1rem', fontWeight: 600 },
      h3: { fontSize: '0.95rem', fontWeight: 600 },
      h4: { fontSize: '0.875rem', fontWeight: 600 },
      h5: { fontSize: '0.8rem', fontWeight: 500 },
      h6: { fontSize: '0.75rem', fontWeight: 500 },
    },
    shadows: [
      'none',
      '0 1px 2px rgba(0, 0, 0, 0.05)',
      '0 4px 12px rgba(0, 0, 0, 0.12)',
    ],
  };
}

function RedmineEmbeddedChatApp({ config, isSidebar, onToggleSidebar }) {
  const [rcTheme] = useState(() => buildRedmineAdaptiveTheme());

  const authProp = config.auth_token
    ? {
      flow: 'TOKEN',
      credentials: {
        resume: config.auth_token,
      },
    }
    : {
      flow: 'PASSWORD',
    };

  useEffect(() => {
    if (config.auth_token && typeof localStorage !== 'undefined') {
      localStorage.setItem('ec_token', config.auth_token);
    }
  }, [config.auth_token]);

  return (
    <EmbeddedChat
      host={config.host}
      roomId={config.room_id || 'GENERAL'}
      channelName={config.channel_name}
      enableThreads={true}
      showAvatar={true}
      showUsername={true}
      hideHeader={false}
      isClosable={isSidebar}
      setClosableState={onToggleSidebar}
      theme={rcTheme}
      width="100%"
      height="100%"
      auth={authProp}
    />
  );
}

// Controller for mounting EmbeddedChat, managing Ticket Threads, #1234 Autocomplete, and intra-project PJAX navigation
class RedmineRocketChatWidget {
  constructor(wrapper) {
    this.wrapper = wrapper;
    this.mountEl = wrapper.querySelector('.rc-EmbeddedMount');
    this.dropdownEl = wrapper.querySelector('.rc-IssueAutocomplete');
    this.dropdownListEl = wrapper.querySelector('.rc-IssueAutocomplete-list');
    this.contextLeftEl = wrapper.querySelector('.rc-ContextBar-left');
    this.threadSwitchBtn = wrapper.querySelector('.rc-ThreadSwitchBtn');
    this.channelSwitchBtn = wrapper.querySelector('.rc-ChannelSwitchBtn');
    this.sidebarToggleBtn = wrapper.querySelector('.rc-SidebarToggleBtn');

    this.projectId = wrapper.dataset.projectId;
    this.channelName = wrapper.dataset.channelName;
    this.rcUrl = wrapper.dataset.rcUrl;
    this.sessionUrl = wrapper.dataset.sessionUrl;
    this.issuesUrl = wrapper.dataset.issuesUrl;
    this.threadBaseUrl = wrapper.dataset.threadBaseUrl;
    this.currentIssueId = wrapper.dataset.issueId || null;
    this.currentIssueSubject = wrapper.dataset.issueSubject || null;
    this.mode = wrapper.dataset.mode || 'tab';

    this.issuesCache = [];
    this.selectedIndex = 0;
    this.activeHashTrigger = null; // { start, end, query }
    this.boundTextarea = null;
    this.debounceTimer = null;

    this.init();
  }

  async init() {
    this.setupSidebarToggle();
    this.setupSidebarResizer();
    this.setupThreadButtons();
    this.setupIntraProjectTurboNavigation();
    await this.loadSessionAndMount();
    this.observeChatInput();
    this.subscribeThreadStore();
  }

  setupSidebarResizer() {
    if (this.mode !== 'sidebar') return;

    const storageKey = 'redmine_rc_sidebar_width';
    const minWidth = 220;
    const maxWidthRatio = 0.7;

    const applyWidth = (px) => {
      const maxWidth = Math.max(minWidth, Math.floor(window.innerWidth * maxWidthRatio));
      const clamped = Math.min(maxWidth, Math.max(minWidth, Math.round(px)));
      document.documentElement.style.setProperty('--rc-sidebar-width', `${clamped}px`);
      return clamped;
    };

    const savedWidth = parseInt(localStorage.getItem(storageKey), 10);
    if (!Number.isNaN(savedWidth) && savedWidth >= minWidth) {
      applyWidth(savedWidth);
    }

    const resizer = document.getElementById('rocketchat-sidebar-resizer');
    if (!resizer || resizer.dataset.rcBound) return;
    resizer.dataset.rcBound = 'true';

    let isDragging = false;

    const onMouseMove = (e) => {
      if (!isDragging) return;
      const newWidth = window.innerWidth - e.clientX;
      applyWidth(newWidth);
    };

    const onMouseUp = (e) => {
      if (!isDragging) return;
      isDragging = false;
      document.body.classList.remove('rc-sidebar-resizing');
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);

      const finalWidth = applyWidth(window.innerWidth - e.clientX);
      localStorage.setItem(storageKey, String(finalWidth));
    };

    resizer.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      isDragging = true;
      document.body.classList.add('rc-sidebar-resizing');
      window.addEventListener('mousemove', onMouseMove);
      window.addEventListener('mouseup', onMouseUp);
    });

    // Double-click resets sidebar width to default (30em)
    resizer.addEventListener('dblclick', () => {
      localStorage.removeItem(storageKey);
      document.documentElement.style.removeProperty('--rc-sidebar-width');
    });

    window.addEventListener('resize', () => {
      const currentSaved = parseInt(localStorage.getItem(storageKey), 10);
      if (!Number.isNaN(currentSaved)) {
        applyWidth(currentSaved);
      }
    });
  }

  setupSidebarToggle() {
    if (this.mode !== 'sidebar') return;

    const isCollapsed = localStorage.getItem('redmine_rc_sidebar_collapsed') === 'true';
    if (isCollapsed) {
      document.body.classList.add('rc-sidebar-collapsed');
    }

    this.bindMainMenuChatTab();

    if (this.sidebarToggleBtn) {
      this.sidebarToggleBtn.addEventListener('click', () => this.toggleSidebar());
    }
  }

  toggleSidebar(forceState = null) {
    const nextCollapsed =
      typeof forceState === 'boolean'
        ? forceState
        : !document.body.classList.contains('rc-sidebar-collapsed');

    document.body.classList.toggle('rc-sidebar-collapsed', nextCollapsed);
    localStorage.setItem('redmine_rc_sidebar_collapsed', nextCollapsed ? 'true' : 'false');

    setTimeout(() => {
      this.syncTopMenuHeight();
      if (typeof window.displayTabsButtons === 'function') {
        window.displayTabsButtons();
      }
    }, 50);

    if (nextCollapsed) {
      this.blinkMainMenuChatTab();
    }
  }

  blinkMainMenuChatTab() {
    const chatTab = document.querySelector('#main-menu li a.rocket-chat');
    if (!chatTab) return;
    chatTab.classList.remove('rc-tab-blink');
    // Force reflow to restart animation
    void chatTab.offsetWidth;
    chatTab.classList.add('rc-tab-blink');
    setTimeout(() => {
      chatTab.classList.remove('rc-tab-blink');
    }, 2400);
  }

  bindMainMenuChatTab() {
    const chatTab = document.querySelector('#main-menu li a.rocket-chat');
    if (!chatTab || chatTab.dataset.rcMenuBound) return;
    chatTab.dataset.rcMenuBound = 'true';

    chatTab.addEventListener(
      'click',
      (e) => {
        const isNarrow = window.matchMedia('(max-width: 1200px)').matches;
        if (!isNarrow) {
          // On wide screens (> 1200px), clicking the right-aligned "Chat" tab re-opens the sidebar in-place
          e.preventDefault();
          e.stopPropagation();
          this.toggleSidebar(false);
        }
        // On narrow screens (<= 1200px), let the link navigate (via PJAX) to /projects/:id/rocket_chat so it opens in the main content area
      },
      true
    );
  }

  setupThreadButtons() {
    this.placeContextualIssueThreadLinks();

    if (this.threadSwitchBtn && !this.threadSwitchBtn.dataset.rcBound) {
      this.threadSwitchBtn.dataset.rcBound = 'true';
      this.threadSwitchBtn.addEventListener('click', () => {
        const issueId = this.threadSwitchBtn.dataset.issueId;
        if (issueId) this.openOrCreateIssueThread(issueId);
      });
    }

    if (this.channelSwitchBtn && !this.channelSwitchBtn.dataset.rcBound) {
      this.channelSwitchBtn.dataset.rcBound = 'true';
      this.channelSwitchBtn.addEventListener('click', () => {
        this.closeThreadView();
      });
    }

    // Listen to any "Open Issue Thread" link rendered inside Redmine's issue contextual bar
    document.querySelectorAll('.rc-OpenIssueThreadBtn').forEach((btn) => {
      if (btn.dataset.rcBound) return;
      btn.dataset.rcBound = 'true';
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        document.body.classList.remove('rc-sidebar-collapsed');
        localStorage.setItem('redmine_rc_sidebar_collapsed', 'false');
        const issueId = btn.dataset.issueId;
        if (issueId) {
          this.openOrCreateIssueThread(issueId);
        }
      });
    });
  }

  // Places the Chat link cleanly between "Bearbeiten" (.icon-edit) and "Beobachten" (a[class*="-watcher"]) in both top & bottom .contextual bars
  placeContextualIssueThreadLinks() {
    const template = document.getElementById('rc-issue-thread-template');
    if (!template) return;

    const contextualBars = document.querySelectorAll('#content > .contextual');
    contextualBars.forEach((bar) => {
      if (bar.querySelector('.rc-ContextualThreadLink')) return;

      const clone = template.cloneNode(true);
      clone.removeAttribute('id');
      clone.style.display = '';

      const editLink = bar.querySelector('a.icon-edit');
      const watchLink = bar.querySelector('a[class*="watcher"], a.icon-fav, a.icon-fav-off');

      if (editLink && editLink.nextSibling) {
        bar.insertBefore(clone, editLink.nextSibling);
      } else if (watchLink) {
        bar.insertBefore(clone, watchLink);
      } else {
        bar.insertBefore(clone, bar.firstChild);
      }
    });

    template.remove();
  }

  // Intercepts intra-project tab/page switches (e.g. Overview <-> Wiki <-> Kanban <-> Issues list)
  // so `#wrapper` is swapped via AJAX while `#rocketchat-sidebar` stays alive without reloading!
  // Full reload happens when switching to another project or entering/leaving an issue detail view (`/issues/123`).
  setupIntraProjectTurboNavigation() {
    if (this.mode !== 'sidebar' || window.__rcTurboNavInstalled) return;
    window.__rcTurboNavInstalled = true;

    const isIssueDetailUrl = (urlObj) => /^\/issues\/\d+(?:\/|$)/.test(urlObj.pathname);

    const shouldInterceptNavigation = (targetUrl) => {
      if (targetUrl.origin !== window.location.origin) return false;
      // Do not intercept if currently on an issue detail page or navigating to an issue detail page
      const currentUrl = new URL(window.location.href);
      if (isIssueDetailUrl(currentUrl) || isIssueDetailUrl(targetUrl)) return false;

      // Skip downloads, attachments, exports, admin, login/logout
      if (
        /\.(pdf|csv|txt|html|atom|xml|json|zip|tar|gz|png|jpg|jpeg|gif)$/i.test(targetUrl.pathname) ||
        targetUrl.pathname.startsWith('/attachments') ||
        targetUrl.pathname.startsWith('/login') ||
        targetUrl.pathname.startsWith('/logout') ||
        targetUrl.pathname.startsWith('/admin') ||
        targetUrl.pathname.startsWith('/settings') ||
        targetUrl.searchParams.has('format')
      ) {
        return false;
      }

      // Check if link clearly belongs to another project (`/projects/<other_identifier>...`)
      const projMatch = targetUrl.pathname.match(/^\/projects\/([^\/]+)/);
      if (projMatch && projMatch[1] !== this.projectId) {
        return false;
      }

      // Intercept project tabs & intra-project links
      if (projMatch && projMatch[1] === this.projectId) {
        return true;
      }

      return false;
    };

    const swapPageWrapper = async (urlStr, pushState = true) => {
      try {
        const indicator = document.getElementById('ajax-indicator');
        if (indicator) indicator.style.display = 'block';

        const res = await fetch(urlStr, {
          method: 'GET',
          headers: { Accept: 'text/html' },
          credentials: 'same-origin',
        });

        if (!res.ok || res.redirected && !shouldInterceptNavigation(new URL(res.url))) {
          window.location.href = res.url || urlStr;
          return;
        }

        const html = await res.text();
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');

        // Verify the target page is still in the same project
        const newSidebar = doc.getElementById('rocketchat-sidebar');
        const newWrapper = doc.getElementById('wrapper');
        if (!newWrapper || !newSidebar) {
          window.location.href = urlStr;
          return;
        }

        // Track the last non-chat project page so if the user widens the window while on `/rocket_chat`,
        // we can automatically return the main view to that page while docking the chat back into the right sidebar!
        const parsedTargetUrl = new URL(res.url || urlStr, window.location.origin);
        if (!/\/rocket_chat(?:\/|$)/.test(parsedTargetUrl.pathname)) {
          window.__rcLastNonChatUrl = parsedTargetUrl.toString();
        }

        // Before replacing #wrapper, park the live primary chat widget back inside #rocketchat-sidebar
        // so it isn't destroyed if it was temporarily docked inside #rocketchat-content on narrow screens
        const liveSidebar = document.getElementById('rocketchat-sidebar');
        if (window.__rcPrimaryWrapper && liveSidebar && window.__rcPrimaryWrapper.parentElement !== liveSidebar) {
          liveSidebar.appendChild(window.__rcPrimaryWrapper);
        }

        // Sync any new stylesheets or scripts in <head> that aren't loaded yet
        const existingHrefs = new Set(
          Array.from(document.head.querySelectorAll('link[rel="stylesheet"]')).map((l) => l.getAttribute('href'))
        );
        doc.head.querySelectorAll('link[rel="stylesheet"]').forEach((link) => {
          const href = link.getAttribute('href');
          if (href && !existingHrefs.has(href)) {
            document.head.appendChild(link.cloneNode(true));
          }
        });

        const existingSrcs = new Set(
          Array.from(document.head.querySelectorAll('script[src]')).map((s) => s.getAttribute('src'))
        );
        const newHeadScripts = [];
        doc.head.querySelectorAll('script[src]').forEach((scr) => {
          const src = scr.getAttribute('src');
          if (src && !existingSrcs.has(src) && !src.includes('rocketchat_embedded')) {
            const s = document.createElement('script');
            s.src = src;
            s.async = false;
            document.head.appendChild(s);
            newHeadScripts.push(s);
          }
        });

        // Update title and body classes (preserving our collapsed class)
        document.title = doc.title;
        const wasCollapsed = document.body.classList.contains('rc-sidebar-collapsed');
        document.body.className = doc.body.className;
        if (wasCollapsed) document.body.classList.add('rc-sidebar-collapsed');

        // Replace #wrapper content
        const currentWrapper = document.getElementById('wrapper');
        currentWrapper.replaceWith(newWrapper);

        if (pushState) {
          window.history.pushState({ rcPjax: true }, doc.title, res.url || urlStr);
        }

        // Execute inline scripts inside the new #wrapper so Redmine/plugin JS (like Kanban, Gantt, Submenus) initializes
        newWrapper.querySelectorAll('script').forEach((oldScript) => {
          if (oldScript.src && oldScript.src.includes('rocketchat_embedded')) return;
          const newScript = document.createElement('script');
          Array.from(oldScript.attributes).forEach((attr) => newScript.setAttribute(attr.name, attr.value));
          newScript.textContent = oldScript.textContent;
          oldScript.parentNode.replaceChild(newScript, oldScript);
        });

        // Re-trigger jQuery ready / DOMContentLoaded handlers if jQuery is present
        if (window.jQuery) {
          window.jQuery(document).trigger('ready');
        }

        // Re-bind any issue thread buttons and main-menu Chat tab in the new DOM
        this.setupThreadButtons();
        this.bindMainMenuChatTab();
        syncResponsiveChatPosition();
        window.scrollTo(0, 0);
      } catch (err) {
        console.warn('Rocket.Chat PJAX fallback to full navigation:', err);
        window.location.href = urlStr;
      } finally {
        const indicator = document.getElementById('ajax-indicator');
        if (indicator) indicator.style.display = 'none';
      }
    };

    this.swapPageWrapper = swapPageWrapper;
    if (!/\/rocket_chat(?:\/|$)/.test(window.location.pathname)) {
      window.__rcLastNonChatUrl = window.location.href;
    }

    document.addEventListener('click', (e) => {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      const link = e.target.closest('a[href]');
      if (!link) return;
      if (link.target && link.target !== '_self') return;
      if (link.dataset.remote || link.dataset.method || link.getAttribute('onclick')) return;

      const href = link.getAttribute('href');
      if (!href || href.startsWith('#') || href.startsWith('javascript:')) return;

      let targetUrl;
      try {
        targetUrl = new URL(href, window.location.origin);
      } catch (_) {
        return;
      }

      // Same page anchor scroll
      if (targetUrl.pathname === window.location.pathname && targetUrl.search === window.location.search && targetUrl.hash) {
        return;
      }

      if (shouldInterceptNavigation(targetUrl)) {
        e.preventDefault();
        swapPageWrapper(targetUrl.toString(), true);
      }
    });

    window.addEventListener('popstate', () => {
      const targetUrl = new URL(window.location.href);
      if (shouldInterceptNavigation(targetUrl)) {
        swapPageWrapper(targetUrl.toString(), false);
      } else {
        window.location.reload();
      }
    });
  }

  subscribeThreadStore() {
    if (!useMessageStore || !useMessageStore.subscribe) return;
    useMessageStore.subscribe((state) => {
      const isOpen = !!state.isThreadOpen;
      if (this.channelSwitchBtn) {
        this.channelSwitchBtn.style.display = isOpen ? 'inline-flex' : 'none';
      }
      if (this.threadSwitchBtn) {
        this.threadSwitchBtn.classList.toggle('is-active', isOpen);
      }
    });
  }

  async loadSessionAndMount() {
    try {
      const url = new URL(this.sessionUrl, window.location.origin);
      if (this.currentIssueId) {
        url.searchParams.set('issue_id', this.currentIssueId);
      }
      const res = await fetch(url.toString(), {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      });
      const config = await res.json();
      this.sessionConfig = config;

      const proxyBaseUrl = `/projects/${this.projectId}/rocket_chat/proxy`;
      installRocketChatFetchProxy(config.host, proxyBaseUrl);

      if (config.auth_token && typeof localStorage !== 'undefined') {
        localStorage.setItem('ec_token', config.auth_token);
      }

      const root = createRoot(this.mountEl);
      root.render(
        <RedmineEmbeddedChatApp
          config={config}
          isSidebar={this.mode === 'sidebar'}
          onToggleSidebar={() => {
            this.toggleSidebar();
          }}
        />
      );

      // If we are on an issue page that already has an active Rocket.Chat thread (or one was just auto-created on issue creation),
      // automatically switch EmbeddedChat directly into that thread once messages have loaded!
      const domThreadBtn = document.querySelector('.rc-ContextualThreadLink[data-thread-id]');
      const fallbackThreadId = domThreadBtn?.dataset?.threadId || this.wrapper.dataset.issueThreadId || null;

      if (config.issue && config.issue.thread_message) {
        this.currentIssueThreadMsg = config.issue.thread_message;
        this.autoEnterIssueThreadWhenReady(config.issue.thread_message);
      } else if ((config.issue && config.issue.thread_id) || fallbackThreadId) {
        const tid = (config.issue && config.issue.thread_id) || fallbackThreadId;
        this.autoEnterIssueThreadByIdWhenReady(tid, this.currentIssueId);
      }
    } catch (err) {
      console.error('Redmine Rocket.Chat: Failed to initialize EmbeddedChat session:', err);
    }
  }

  autoEnterIssueThreadWhenReady(rawThreadMsg) {
    const msg = this.normalizeMessageForStore(rawThreadMsg);
    let entered = false;

    const tryEnter = () => {
      if (entered) return;
      const store = useMessageStore.getState();
      if (!store || !store.isMessageLoaded || !Array.isArray(store.messages) || store.messages.length === 0) return;

      entered = true;
      const existingMsg = store.messages.find((m) => m && m._id === msg._id) || msg;
      if (store.upsertMessage) {
        store.upsertMessage(existingMsg, false);
      }
      setTimeout(() => {
        const latestStore = useMessageStore.getState();
        if (latestStore && latestStore.openThread) {
          latestStore.openThread(existingMsg);
        }
      }, 150);
    };

    tryEnter();
    if (!entered && useMessageStore.subscribe) {
      const unsub = useMessageStore.subscribe((state) => {
        if (state.isMessageLoaded && Array.isArray(state.messages) && state.messages.length > 0 && !entered) {
          tryEnter();
          if (typeof unsub === 'function') unsub();
        }
      });
    }
  }

  autoEnterIssueThreadByIdWhenReady(threadId, issueId) {
    if (!threadId) return;
    let entered = false;

    const tryEnter = () => {
      if (entered) return;
      const store = useMessageStore.getState();
      if (!store || !store.isMessageLoaded || !Array.isArray(store.messages) || store.messages.length === 0) return;

      const existingMsg = store.messages.find((m) => m && m._id === threadId);
      if (existingMsg) {
        entered = true;
        setTimeout(() => {
          const latestStore = useMessageStore.getState();
          if (latestStore && latestStore.openThread) {
            latestStore.openThread(existingMsg);
          }
        }, 150);
      } else if (issueId) {
        entered = true;
        this.openOrCreateIssueThread(issueId);
      }
    };

    tryEnter();
    if (!entered && useMessageStore.subscribe) {
      const unsub = useMessageStore.subscribe((state) => {
        if (state.isMessageLoaded && Array.isArray(state.messages) && state.messages.length > 0 && !entered) {
          tryEnter();
          if (typeof unsub === 'function') unsub();
        }
      });
    }
  }

  async openOrCreateIssueThread(issueId) {
    try {
      if (this.threadSwitchBtn) {
        this.threadSwitchBtn.disabled = true;
      }
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || '';
      const res = await fetch(`${this.threadBaseUrl}/${issueId}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-CSRF-Token': csrfToken,
        },
        credentials: 'same-origin',
      });
      const data = await res.json();
      if (data.success && data.thread_message) {
        const msg = this.normalizeMessageForStore(data.thread_message);
        const store = useMessageStore.getState();

        // Find existing message in store if already synced via WebSocket, or upsert our normalized message
        const targetMsg = (store.messages || []).find((m) => m && m._id === msg._id) || msg;
        if (store.upsertMessage) {
          store.upsertMessage(targetMsg, false);
        }
        if (store.openThread) {
          store.openThread(targetMsg);
        }

        // Focus the chat input immediately so the user can type right into the new thread
        setTimeout(() => {
          const textarea = this.mountEl.querySelector('textarea');
          if (textarea) textarea.focus();
        }, 120);

        document.querySelectorAll(`.rc-ContextualThreadLink[data-issue-id="${issueId}"]`).forEach((linkEl) => {
          linkEl.classList.add('is-active');
          if (linkEl.dataset.activeTooltip) {
            linkEl.title = linkEl.dataset.activeTooltip;
          }
        });
      } else {
        alert(data.error || 'Ticket-Thread konnte nicht geöffnet werden.');
      }
    } catch (err) {
      console.error('Redmine Rocket.Chat: Error opening issue thread:', err);
    } finally {
      if (this.threadSwitchBtn) {
        this.threadSwitchBtn.disabled = false;
      }
    }
  }

  closeThreadView() {
    const store = useMessageStore.getState();
    if (store && store.closeThread) {
      store.closeThread();
    }
  }

  normalizeMessageForStore(msg) {
    return {
      ...msg,
      ts: msg.ts || new Date().toISOString(),
      u: msg.u || { _id: 'redmine', username: 'redmine', name: 'Redmine' },
      md: msg.md || [
        {
          type: 'PARAGRAPH',
          value: [{ type: 'PLAIN_TEXT', value: msg.msg || '' }],
        },
      ],
    };
  }

  observeChatInput() {
    const check = () => {
      const textarea = this.mountEl.querySelector('textarea');
      if (textarea && textarea !== this.boundTextarea) {
        this.boundTextarea = textarea;
        this.attachTextareaListeners(textarea);
      }
      this.syncTopMenuHeight();
      this.rewriteMediaUrlsToProxy();
    };

    check();
    const observer = new MutationObserver(check);
    observer.observe(this.mountEl, { childList: true, subtree: true });
    window.addEventListener('resize', () => this.syncTopMenuHeight());
  }

  // Rewrites Rocket.Chat `/file-upload/...` and `/ufs/...` media URLs on <img>, <source>, <audio>, and <a> tags
  // to go through our authenticated Redmine proxy so images & downloads work without 403 Forbidden
  rewriteMediaUrlsToProxy() {
    if (!this.rcUrl || !window.__rcProxyBaseUrl) return;
    const cleanHost = this.rcUrl.replace(/\/$/, '');
    const proxyBase = window.__rcProxyBaseUrl;

    const rewriteAttr = (el, attr) => {
      const val = el.getAttribute(attr);
      if (!val) return;
      if (val.startsWith(cleanHost + '/file-upload/') || val.startsWith(cleanHost + '/ufs/')) {
        const rel = val.slice(cleanHost.length + 1);
        el.setAttribute(attr, `${proxyBase}/${rel}`);
      } else if (val.startsWith('/file-upload/') || val.startsWith('/ufs/')) {
        el.setAttribute(attr, `${proxyBase}${val}`);
      }
    };

    this.mountEl.querySelectorAll('img[src], source[src], audio[src]').forEach((el) => rewriteAttr(el, 'src'));
    this.mountEl.querySelectorAll('a[href]').forEach((el) => rewriteAttr(el, 'href'));
  }

  syncTopMenuHeight() {
    const topMenuEl = document.getElementById('top-menu');
    if (topMenuEl) {
      const h = Math.round(topMenuEl.getBoundingClientRect().height);
      if (h >= 18) {
        document.documentElement.style.setProperty('--rc-top-menu-height', `${h}px`);
      }
    }
    const tabsButtonsEl = document.querySelector('#main-menu .tabs-buttons');
    if (tabsButtonsEl) {
      const btnStyle = window.getComputedStyle(tabsButtonsEl);
      const isVisible = btnStyle.display !== 'none' && btnStyle.visibility !== 'hidden';
      const btnWidth = isVisible ? Math.round(tabsButtonsEl.getBoundingClientRect().width) : 0;
      const rightOffset = btnWidth > 0 ? btnWidth + 14 : 16;
      document.documentElement.style.setProperty('--rc-tabs-buttons-offset', `${rightOffset}px`);
    }
  }

  attachTextareaListeners(textarea) {
    textarea.addEventListener(
      'keydown',
      (e) => {
        if (!this.isDropdownVisible()) return;

        if (e.key === 'ArrowDown') {
          e.preventDefault();
          e.stopPropagation();
          this.selectedIndex = (this.selectedIndex + 1) % Math.max(1, this.issuesCache.length);
          this.renderDropdownItems();
        } else if (e.key === 'ArrowUp') {
          e.preventDefault();
          e.stopPropagation();
          this.selectedIndex =
            (this.selectedIndex - 1 + Math.max(1, this.issuesCache.length)) %
            Math.max(1, this.issuesCache.length);
          this.renderDropdownItems();
        } else if (e.key === 'Enter' || e.key === 'Tab') {
          if (this.issuesCache.length > 0) {
            e.preventDefault();
            e.stopPropagation();
            const chosen = this.issuesCache[this.selectedIndex] || this.issuesCache[0];
            if (e.shiftKey) {
              this.selectIssueForThread(chosen);
            } else {
              this.insertIssueLink(chosen);
            }
          }
        } else if (e.key === 'Escape') {
          e.preventDefault();
          e.stopPropagation();
          this.hideDropdown();
        }
      },
      true
    );

    textarea.addEventListener('input', () => {
      this.handleTextareaInput(textarea);
    });

    textarea.addEventListener('click', () => {
      this.handleTextareaInput(textarea);
    });

    document.addEventListener('click', (e) => {
      if (
        this.isDropdownVisible() &&
        !this.dropdownEl.contains(e.target) &&
        e.target !== textarea
      ) {
        this.hideDropdown();
      }
    });
  }

  handleTextareaInput(textarea) {
    const val = textarea.value;
    const cursor = textarea.selectionStart || 0;
    const beforeCursor = val.slice(0, cursor);

    const match = beforeCursor.match(/(?:^|\s)#([a-zA-Z0-9äöüÄÖÜß_\-]{0,30})$/);
    if (!match) {
      this.hideDropdown();
      return;
    }

    const query = match[1] || '';
    const hashStart = beforeCursor.lastIndexOf('#');
    this.activeHashTrigger = {
      start: hashStart,
      end: cursor,
      query: query,
    };

    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.fetchIssues(query);
    }, 120);
  }

  async fetchIssues(query) {
    try {
      const url = new URL(this.issuesUrl, window.location.origin);
      url.searchParams.set('q', query);
      const res = await fetch(url.toString(), {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      });
      const data = await res.json();
      this.issuesCache = data.issues || [];
      this.selectedIndex = 0;
      this.renderDropdownItems();
      this.showDropdown();
    } catch (err) {
      console.error('Redmine Rocket.Chat: Error fetching issues for autocomplete:', err);
    }
  }

  renderDropdownItems() {
    if (!this.dropdownListEl) return;
    this.dropdownListEl.innerHTML = '';

    if (this.issuesCache.length === 0) {
      const emptyLi = document.createElement('li');
      emptyLi.className = 'rc-IssueAutocomplete-item';
      emptyLi.style.color = '#64748b';
      emptyLi.textContent = 'Keine passenden Tickets gefunden';
      this.dropdownListEl.appendChild(emptyLi);
      return;
    }

    this.issuesCache.forEach((issue, idx) => {
      const li = document.createElement('li');
      li.className = `rc-IssueAutocomplete-item ${idx === this.selectedIndex ? 'is-selected' : ''}`;

      const mainDiv = document.createElement('div');
      mainDiv.className = 'rc-IssueAutocomplete-main';

      const titleDiv = document.createElement('div');
      titleDiv.className = 'rc-IssueAutocomplete-title';
      titleDiv.innerHTML = `<span class="rc-issue-id">#${issue.id}</span> ${this.escapeHtml(issue.subject)}`;

      const metaDiv = document.createElement('div');
      metaDiv.className = 'rc-IssueAutocomplete-meta';
      const parts = [issue.tracker, issue.status];
      if (issue.assigned_to) parts.push(`→ ${issue.assigned_to}`);
      if (issue.thread_id) parts.push('💬 Thread aktiv');
      metaDiv.textContent = parts.filter(Boolean).join(' · ');

      mainDiv.appendChild(titleDiv);
      mainDiv.appendChild(metaDiv);

      const actionsDiv = document.createElement('div');
      actionsDiv.className = 'rc-IssueAutocomplete-actions';

      const linkBtn = document.createElement('button');
      linkBtn.type = 'button';
      linkBtn.className = 'rc-IssueAutocomplete-actionBtn';
      linkBtn.textContent = 'Link';
      linkBtn.title = 'Ticket-Link in Nachricht einfügen (Enter)';
      linkBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        this.insertIssueLink(issue);
      });

      const threadBtn = document.createElement('button');
      threadBtn.type = 'button';
      threadBtn.className = 'rc-IssueAutocomplete-actionBtn is-thread';
      threadBtn.textContent = '💬 Thread';
      threadBtn.title = 'Ticket-Thread öffnen oder starten (Shift+Enter)';
      threadBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        this.selectIssueForThread(issue);
      });

      actionsDiv.appendChild(linkBtn);
      actionsDiv.appendChild(threadBtn);

      li.appendChild(mainDiv);
      li.appendChild(actionsDiv);

      li.addEventListener('mouseenter', () => {
        this.selectedIndex = idx;
        Array.from(this.dropdownListEl.children).forEach((el, i) => {
          el.classList.toggle('is-selected', i === idx);
        });
      });

      li.addEventListener('click', () => {
        this.insertIssueLink(issue);
      });

      this.dropdownListEl.appendChild(li);
    });

    const selectedEl = this.dropdownListEl.children[this.selectedIndex];
    if (selectedEl && selectedEl.scrollIntoView) {
      selectedEl.scrollIntoView({ block: 'nearest' });
    }
  }

  insertIssueLink(issue) {
    const textarea = this.boundTextarea;
    if (!textarea || !this.activeHashTrigger) return;

    const val = textarea.value;
    const before = val.slice(0, this.activeHashTrigger.start);
    const after = val.slice(this.activeHashTrigger.end);

    const markdownLink = `[#${issue.id}: ${issue.subject}](${issue.url}) `;
    const nextValue = `${before}${markdownLink}${after}`;

    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
      window.HTMLTextAreaElement.prototype,
      'value'
    )?.set;
    if (nativeInputValueSetter) {
      nativeInputValueSetter.call(textarea, nextValue);
    } else {
      textarea.value = nextValue;
    }

    const newCursor = before.length + markdownLink.length;
    textarea.setSelectionRange(newCursor, newCursor);
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
    textarea.dispatchEvent(new Event('change', { bubbles: true }));
    textarea.focus();

    this.hideDropdown();
  }

  selectIssueForThread(issue) {
    const textarea = this.boundTextarea;
    if (textarea && this.activeHashTrigger) {
      const val = textarea.value;
      const before = val.slice(0, this.activeHashTrigger.start);
      const after = val.slice(this.activeHashTrigger.end);
      const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
        window.HTMLTextAreaElement.prototype,
        'value'
      )?.set;
      if (nativeInputValueSetter) {
        nativeInputValueSetter.call(textarea, `${before}${after}`);
      } else {
        textarea.value = `${before}${after}`;
      }
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
    }
    this.hideDropdown();
    this.openOrCreateIssueThread(issue.id);
  }

  isDropdownVisible() {
    return this.dropdownEl && this.dropdownEl.style.display !== 'none';
  }

  showDropdown() {
    if (this.dropdownEl) {
      this.dropdownEl.style.display = 'flex';
    }
  }

  hideDropdown() {
    if (this.dropdownEl) {
      this.dropdownEl.style.display = 'none';
    }
    this.activeHashTrigger = null;
  }

  escapeHtml(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
}

function syncResponsiveChatPosition() {
  const sidebarEl = document.getElementById('rocketchat-sidebar');
  const tabContentEl = document.getElementById('rocketchat-content');

  // If sidebar is NOT present on the page (i.e. show_sidebar setting is false), mount normal tab widget
  if (!sidebarEl) {
    document.querySelectorAll('.rc-embedded-wrapper').forEach((wrapper) => {
      if (wrapper.dataset.rcInitialized) return;
      wrapper.dataset.rcInitialized = 'true';
      window.__rcPrimaryWidget = new RedmineRocketChatWidget(wrapper);
    });
    return;
  }

  // Ensure the single primary widget instance is initialized once
  let primaryWrapper = window.__rcPrimaryWrapper || sidebarEl.querySelector('.rc-embedded-wrapper');
  if (!primaryWrapper) return;
  window.__rcPrimaryWrapper = primaryWrapper;

  if (!primaryWrapper.dataset.rcInitialized) {
    primaryWrapper.dataset.rcInitialized = 'true';
    window.__rcPrimaryWidget = new RedmineRocketChatWidget(primaryWrapper);
  }

  // Remove any duplicate uninitialized wrapper inside #rocketchat-content so two EmbeddedChat instances never clash
  if (tabContentEl) {
    Array.from(tabContentEl.querySelectorAll('.rc-embedded-wrapper')).forEach((w) => {
      if (w !== primaryWrapper) {
        w.remove();
      }
    });
  }

  const isNarrow = window.matchMedia('(max-width: 1200px)').matches;
  const wasNarrow = window.__rcWasNarrow;
  window.__rcWasNarrow = isNarrow;

  if (isNarrow && wasNarrow === false && window.__rcPrimaryWidget) {
    window.__rcPrimaryWidget.blinkMainMenuChatTab();
  }

  if (isNarrow && tabContentEl) {
    if (primaryWrapper.parentElement !== tabContentEl) {
      tabContentEl.appendChild(primaryWrapper);
    }
  } else {
    const wasInTabContent = tabContentEl && primaryWrapper.parentElement === tabContentEl;
    if (primaryWrapper.parentElement !== sidebarEl) {
      sidebarEl.appendChild(primaryWrapper);
    }

    // If the user was actively viewing the `/rocket_chat` tab on a narrow window and just widened the window (> 1200px):
    // 1. Ensure the right sidebar is expanded (even if it was previously collapsed) so the chat doesn't disappear!
    // 2. Navigate the main left area back to the last non-chat project page (or project overview) so it's not an empty white page.
    if (wasInTabContent || (!isNarrow && tabContentEl && /\/rocket_chat(?:\/|$)/.test(window.location.pathname))) {
      if (window.__rcPrimaryWidget) {
        window.__rcPrimaryWidget.toggleSidebar(false);
      } else {
        document.body.classList.remove('rc-sidebar-collapsed');
        localStorage.setItem('redmine_rc_sidebar_collapsed', 'false');
      }

      if (wasInTabContent && window.__rcPrimaryWidget && typeof window.__rcPrimaryWidget.swapPageWrapper === 'function') {
        const firstMenuTab = document.querySelector('#main-menu ul li a:not(.rocket-chat):not(.new-object)');
        const fallbackUrl =
          window.__rcLastNonChatUrl ||
          (firstMenuTab ? firstMenuTab.href : `/projects/${primaryWrapper.dataset.projectId}`);
        window.__rcPrimaryWidget.swapPageWrapper(fallbackUrl, true);
      }
    }
  }
}

function bootRedmineRocketChat() {
  syncResponsiveChatPosition();
  window.addEventListener('resize', syncResponsiveChatPosition);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootRedmineRocketChat);
} else {
  bootRedmineRocketChat();
}
