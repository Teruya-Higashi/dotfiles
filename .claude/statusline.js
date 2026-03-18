#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Read JSON from stdin
let input = '';
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);

    // Extract values
    const model = data.model?.display_name || 'Unknown';
    const currentDir = data.workspace?.current_dir || data.cwd || '.';
    const dirName = path.basename(currentDir);

    // Get effort level from settings (local > project > user)
    const effort = getEffortLevel(currentDir);

    // Get Git branch
    let branch = '';
    if (currentDir && fs.existsSync(path.join(currentDir, '.git'))) {
      try {
        const branchName = execSync('git --no-optional-locks branch --show-current 2>/dev/null', {
          cwd: currentDir,
          encoding: 'utf-8'
        }).trim();
        if (branchName) {
          branch = `${branchName}`;
        }
      } catch (_e) {
        // Gitコマンドエラーは無視
      }
    }

    // Context usage — Claude Code provides pre-calculated percentages
    const cw = data.context_window || {};
    const percentage = cw.used_percentage ?? 0;
    const contextSize = cw.context_window_size ?? 200000;

    // Estimate token count from percentage and context window size
    const estimatedTokens = Math.round((percentage / 100) * contextSize);
    const tokenDisplay = formatTokenCount(estimatedTokens);

    // Color coding for percentage
    let percentageColor = '\x1b[32m'; // Green
    if (percentage >= 56) percentageColor = '\x1b[33m'; // Yellow
    if (percentage >= 72) percentageColor = '\x1b[91m'; // Bright Red

    // Build status line: [Model:effort] tokens (percentage%)
    const effortDisplay = effort ? `:${effort}` : '';
    const statusLine = `${dirName} - ${branch}\n[${model}${effortDisplay}] ${percentageColor}${percentage}%\x1b[0m\x1b[90m (${tokenDisplay})`;

    console.log(statusLine);
  } catch (_error) {
    // Fallback status line on error
    console.log('[Claude Code]');
  }
});


function getEffortLevel(currentDir) {
  // 1. Environment variable (highest priority, same as Claude Code internal logic)
  const envEffort = process.env.CLAUDE_CODE_EFFORT_LEVEL;
  if (envEffort) {
    const lower = envEffort.toLowerCase();
    if (lower === 'unset' || lower === 'auto') return null;
    if (['low', 'medium', 'high'].includes(lower)) return lower;
  }

  // 2. Settings files (local > project > user)
  const settingsFiles = [
    path.join(currentDir, '.claude', 'settings.local.json'),
    path.join(currentDir, '.claude', 'settings.json'),
    path.join(process.env.HOME, '.claude', 'settings.json'),
  ];

  for (const file of settingsFiles) {
    try {
      if (fs.existsSync(file)) {
        const settings = JSON.parse(fs.readFileSync(file, 'utf-8'));
        if (settings.effortLevel) {
          return settings.effortLevel;
        }
      }
    } catch (_e) {
      // skip unreadable settings
    }
  }
  return null;
}

function formatTokenCount(tokens) {
  if (tokens >= 1000000) {
    return `${(tokens / 1000000).toFixed(1)} M`;
  } else if (tokens >= 1000) {
    return `${(tokens / 1000).toFixed(1)} K`;
  }
  return tokens.toString();
}
