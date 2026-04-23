#!/usr/bin/env node

const path = require('path');
const { execSync } = require('child_process');

const R = '\x1b[0m';
const LABEL = '\x1b[38;2;170;170;170m';
const BOLD = '\x1b[1m';

const RINGS = ['○', '◔', '◑', '◕', '●'];

function gradient(pct) {
  if (pct < 50) {
    const r = Math.round(pct * 5.1);
    return `\x1b[38;2;${r};200;80m`;
  }
  const g = Math.round(200 - (pct - 50) * 4);
  return `\x1b[38;2;255;${Math.max(g, 0)};60m`;
}

function ring(pct) {
  const idx = Math.min(Math.floor(pct / 25), 4);
  return RINGS[idx];
}

function fmt(label, pct) {
  const p = Math.round(pct);
  return `${LABEL}${label}${R} ${gradient(pct)}${ring(pct)} ${p}%${R}`;
}

function getGitBranch(dir) {
  try {
    return execSync('git --no-optional-locks branch --show-current 2>/dev/null', {
      cwd: dir, encoding: 'utf-8'
    }).trim();
  } catch (_e) {
    return '';
  }
}

let input = '';
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);

    const currentDir = data.workspace?.current_dir || data.cwd || '.';
    const dirName = path.basename(currentDir);
    const branch = getGitBranch(currentDir);
    const header = branch ? `${dirName} - ${branch}` : dirName;

    const model = `${BOLD}${data.model?.display_name || 'Claude'}${R}`;

    const usages = [];

    const contextWindow = data.context_window?.used_percentage;
    if (contextWindow != null) usages.push(fmt('ctx:', contextWindow));

    const fiveHour = data.rate_limits?.five_hour?.used_percentage;
    if (fiveHour != null) usages.push(fmt('5h:', fiveHour));

    const sevenDay = data.rate_limits?.seven_day?.used_percentage;
    if (sevenDay != null) usages.push(fmt('7d:', sevenDay));

    process.stdout.write(`${header}\n${model}\n${usages.join(' | ')}`);
  } catch (_e) {
    process.stdout.write('[Claude Code]');
  }
});
