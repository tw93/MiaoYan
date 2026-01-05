#!/usr/bin/env node
/**
 * Generate the sponsor board SVG and keep the friend list embedded in CSS in sync.
 *
 * Usage:
 *   node scripts/generate-sponsors.js
 *
 * The script will look for SPONSORS_TOKEN / GH_TOKEN / GITHUB_TOKEN to request
 * sponsor data from the GitHub GraphQL API. When no token is available it falls
 * back to rendering only the friend list and a call-to-action link.
 */
const fsp = require('fs/promises');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const FRIENDS_PATH = path.join(ROOT, 'data', 'friends.json');
const CSS_PATH = path.join(ROOT, 'tailwind.css');
const OUTPUT_DIR = path.join(ROOT, 'assets');
const OUTPUT_PATH = path.join(OUTPUT_DIR, 'sponsors.svg');
const SPONSORS_URL = 'https://github.com/sponsors/tw93';
const OWNER_LOGIN = 'tw93';
const GRAPHQL_ENDPOINT = 'https://api.github.com/graphql';
const FONT_FAMILY = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji'";

async function main() {
  const friends = await loadFriends();
  await Promise.all([
    updateTailwindCss(friends),
    ensureDir(OUTPUT_DIR),
  ]);

  const sponsorToken =
    process.env.SPONSORS_TOKEN ||
    process.env.GH_TOKEN ||
    process.env.GITHUB_TOKEN;

  const sponsors = await fetchSponsors(sponsorToken);
  const svgContent = await buildSvg({ sponsors, friends });
  await fsp.writeFile(OUTPUT_PATH, svgContent, 'utf8');
  console.log(
    `Generated ${path.relative(ROOT, OUTPUT_PATH)} with ${sponsors.length} sponsors and ${friends.length} friends.`,
  );
}

async function loadFriends() {
  const raw = await fsp.readFile(FRIENDS_PATH, 'utf8');
  const list = JSON.parse(raw);
  if (!Array.isArray(list)) {
    throw new Error(`Friend data must be an array in ${FRIENDS_PATH}`);
  }
  return list.map((name) => String(name).trim()).filter(Boolean);
}

async function ensureDir(target) {
  await fsp.mkdir(target, { recursive: true });
}

async function updateTailwindCss(friends) {
  let css = await fsp.readFile(CSS_PATH, 'utf8');
  const listJoined = friends.join('、');
  css = replaceCssContent(css, /--data-friend:\s*'/, listJoined);

  const friendCount = friends.length;
  const zhDesc = `数据每日自动更新，当前 ${friendCount} 位朋友喜欢汤圆可乐`;
  const enDesc = `Daily sync · ${friendCount} friends like TangYuan & Coke`;
  css = replaceCssContent(css, /\.i18n-miao-people-desc:before\s*\{\s*content:\s*'/, zhDesc);
  css = replaceCssContent(
    css,
    /\[lang='en'\]\s*\.i18n-miao-people-desc:before\s*\{\s*content:\s*'/,
    enDesc,
  );

  await fsp.writeFile(CSS_PATH, css, 'utf8');
}

function replaceCssContent(css, markerRegex, value) {
  const match = css.match(new RegExp(`${markerRegex.source}([^']*)'`));
  if (!match) {
    throw new Error(`Unable to locate CSS marker: ${markerRegex}`);
  }
  const [snippet, existing] = match;
  const startIndex = match.index;
  const prefix = css.slice(0, startIndex);
  const suffix = css.slice(startIndex + snippet.length);
  return `${prefix}${snippet.replace(existing, value)}${suffix}`;
}

async function fetchSponsors(token) {
  if (!token) {
    console.warn('⚠️  No GitHub token available, sponsor avatars will be skipped.');
    return [];
  }

  const sponsors = [];
  let cursor = null;
  const headers = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
    'User-Agent': 'miaoyan-sponsor-bot',
  };

  while (true) {
    const body = {
      query: `
        query($login: String!, $cursor: String) {
          user(login: $login) {
            sponsorshipsAsMaintainer(first: 100, after: $cursor, includePrivate: true, activeOnly: false, orderBy: {field: CREATED_AT, direction: DESC}) {
              nodes {
                sponsorEntity {
                  ... on User {
                    login
                    name
                    avatarUrl
                    url
                  }
                  ... on Organization {
                    login
                    name
                    avatarUrl
                    url
                  }
                }
                tier {
                  monthlyPriceInDollars
                }
                createdAt
              }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
          }
        }
      `,
      variables: {
        login: OWNER_LOGIN,
        cursor,
      },
    };

    const res = await fetch(GRAPHQL_ENDPOINT, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Failed to fetch sponsors (${res.status}): ${text}`);
    }

    const payload = await res.json();
    const data = payload?.data?.user?.sponsorshipsAsMaintainer;
    if (!data) {
      throw new Error('Unexpected response from GitHub Sponsors API.');
    }

    for (const node of data.nodes || []) {
      const sponsor = node?.sponsorEntity;
      if (!sponsor?.login || !sponsor?.avatarUrl) continue;
      sponsors.push({
        login: sponsor.login,
        name: sponsor.name || sponsor.login,
        avatarUrl: sponsor.avatarUrl,
        url: sponsor.url || `https://github.com/${sponsor.login}`,
        amount: node?.tier?.monthlyPriceInDollars || 0,
        createdAt: node?.createdAt,
      });
    }

    if (!data.pageInfo?.hasNextPage) {
      break;
    }
    cursor = data.pageInfo.endCursor;
  }

  sponsors.sort((a, b) => {
    if (b.amount !== a.amount) return b.amount - a.amount;
    if (a.createdAt && b.createdAt) {
      return new Date(a.createdAt) - new Date(b.createdAt);
    }
    return a.login.localeCompare(b.login);
  });

  return sponsors;
}

async function buildSvg({ sponsors, friends }) {
  const width = 1000;
  const outerPadding = 40;
  const innerPadding = 32;
  const contentWidth = width - outerPadding * 2;
  await embedAvatarData(sponsors);

  let cursorY = innerPadding;
  const defs = [];

  const sponsorGrid = renderSponsorGrid({
    sponsors,
    x: 0,
    y: cursorY,
    width: contentWidth,
  });
  defs.push(...sponsorGrid.defs);
  cursorY += sponsorGrid.height + 90;

  const friendTable = renderFriendTable({
    friends,
    x: 0,
    y: cursorY,
    width: contentWidth,
  });
  cursorY += friendTable.height + innerPadding;

  const boardHeight = cursorY;
  const height = boardHeight + outerPadding * 2;

  const svg = `<svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" role="img">
    <title>Tw93 Sponsors</title>
    <defs>
      ${defs.join('\n')}
    </defs>
    <g transform="translate(${outerPadding}, ${outerPadding})" font-family="${FONT_FAMILY}">
      ${sponsorGrid.markup}
      ${friendTable.markup}
    </g>
  </svg>`;

  return svg;
}

async function avatarDataUri(url) {
  const sizedUrl = url.includes('?') ? `${url}&s=160` : `${url}?s=160`;
  const res = await fetch(sizedUrl);
  if (!res.ok) {
    throw new Error(`Failed to download avatar: ${url}`);
  }
  const contentType = res.headers.get('content-type') || 'image/png';
  const buffer = Buffer.from(await res.arrayBuffer());
  return `data:${contentType};base64,${buffer.toString('base64')}`;
}

async function embedAvatarData(sponsors) {
  for (const sponsor of sponsors) {
    if (!sponsor.avatarUrl) continue;
    try {
      sponsor.avatar = await avatarDataUri(sponsor.avatarUrl);
    } catch (err) {
      console.warn(`Unable to download avatar for ${sponsor.login}: ${err.message}`);
    }
  }
}

function renderSponsorGrid({ sponsors, x, y, width }) {
  const avatarSize = 72;
  const baseGap = 40;
  const gapY = 45;
  let cols = Math.floor(width / (avatarSize + baseGap));
  const rows = Math.max(1, Math.ceil(sponsors.length / cols));
  let spacing = baseGap;
  if (cols > 1) {
    spacing = (width - cols * avatarSize) / (cols - 1);
    if (spacing < baseGap) {
      spacing = baseGap;
      cols = Math.max(1, Math.floor((width + baseGap) / (avatarSize + baseGap)));
    }
  }
  const gridWidth = sponsors.length
    ? cols * avatarSize + Math.max(0, cols - 1) * spacing
    : width;
  const gridHeight = sponsors.length
    ? rows * avatarSize + Math.max(0, rows - 1) * gapY
    : 140;
  const titleHeight = 36;
  const sectionHeight = titleHeight + 36 + gridHeight + 32;
  const centerX = width / 2;
  const offsetX = Math.max(0, (width - gridWidth) / 2);
  let markup = `
    <g transform="translate(${x}, ${y})">
      <text x="${centerX}" y="0" text-anchor="middle" font-size="28" font-weight="600" fill="#222222">GitHub Sponsors (${sponsors.length})</text>
  `;
  const clipDefs = [];

    if (!sponsors.length) {
    markup += `
      <g transform="translate(0, 60)">
        <text x="${width / 2}" y="50" text-anchor="middle" font-size="20" font-weight="500" fill="#666666">Become the first Sponsor</text>
        <a xlink:href="${SPONSORS_URL}" target="_blank">
          <text x="${width / 2}" y="85" text-anchor="middle" font-size="15" fill="#999999">Click to support tw93</text>
        </a>
      </g>
    </g>`;
    return { markup, height: sectionHeight, defs: [] };
  }

  markup += `
    <g transform="translate(0, 60)">
  `;

  sponsors.forEach((sponsor, index) => {
    const col = index % cols;
    const row = Math.floor(index / cols);
    const avatarX = offsetX + col * (avatarSize + spacing);
    const avatarY = row * (avatarSize + gapY);
    const clipId = `cp-${sponsor.login}`;
    clipDefs.push(
      `<clipPath id="${clipId}">
        <circle cx="${avatarSize / 2}" cy="${avatarSize / 2}" r="${avatarSize / 2}" />
      </clipPath>`,
    );
    markup += `
      <g transform="translate(${avatarX}, ${avatarY})">
        ${
          sponsor.avatar
            ? `<image href="${sponsor.avatar}" x="0" y="0" width="${avatarSize}" height="${avatarSize}" clip-path="url(#${clipId})" />`
            : `<circle cx="${avatarSize / 2}" cy="${avatarSize / 2}" r="${avatarSize / 2}" fill="rgba(0,0,0,0.05)" />`
        }
        <text x="${avatarSize / 2}" y="${avatarSize + 22}" text-anchor="middle" font-size="12" fill="#555555">${escapeText(sponsor.name).slice(0, 18)}</text>
      </g>
    `;
  });

  markup += '</g></g>';

  return {
    markup,
    height: sectionHeight,
    defs: clipDefs,
  };
}

function renderFriendTable({ friends, x, y, width }) {
  const titleY = 0;
  const tableTop = 44;
  const columns = 8;
  const colWidth = width / columns;
  const rowHeight = 32;
  const rows = Math.max(1, Math.ceil(friends.length / columns));
  const tableHeight = rows * rowHeight;
  const centerX = width / 2;
  let markup = `
    <g transform="translate(${x}, ${y})">
      <text x="${centerX}" y="0" text-anchor="middle" font-size="28" font-weight="600" fill="#222222">Tipping Friends (${friends.length})</text>
      <g transform="translate(0, 52)">
  `;

  const orderedFriends = [...friends].reverse();
  orderedFriends.forEach((name, index) => {
    const row = Math.floor(index / columns);
    const col = index % columns;
    const textX = col * colWidth + colWidth / 2;
    const textY = row * rowHeight + rowHeight / 2;
    markup += `<text x="${textX}" y="${textY}" text-anchor="middle" alignment-baseline="middle" font-size="14" fill="#555555">${escapeText(name)}</text>`;
  });

  markup += '</g></g>';

  return {
    markup,
    height: tableTop + tableHeight,
  };
}

function escapeText(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function escapeAttr(value) {
  return escapeText(value).replace(/"/g, '&quot;');
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
