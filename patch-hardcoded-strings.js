const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const jsPath = 'C:/Program Files/WindowsApps/Claude_1.8555.2.0_x64__pzs8sxrjxfjjc/app/resources/ion-dist/assets/v1/index-DuIwZ1hn.js';

// Find the actual JS file (version may change)
function findJsFile() {
  const base = 'C:/Program Files/WindowsApps/';
  const dirs = fs.readdirSync(base).filter(d => d.startsWith('Claude_'));
  for (const dir of dirs) {
    const p = path.join(base, dir, 'app/resources/ion-dist/assets/v1/');
    if (fs.existsSync(p)) {
      const files = fs.readdirSync(p).filter(f => f.startsWith('index-') && f.endsWith('.js'));
      if (files.length > 0) return path.join(p, files[0]);
    }
  }
  return null;
}

const actualPath = findJsFile() || jsPath;

if (!fs.existsSync(actualPath)) {
  console.error('找不到 ion-dist JS 文件，请确认 Claude Desktop 已安装');
  process.exit(1);
}

console.log('目标文件:', actualPath);

// Backup
const backupPath = actualPath + '.bak';
if (!fs.existsSync(backupPath)) {
  fs.copyFileSync(actualPath, backupPath);
  console.log('已创建备份:', path.basename(backupPath));
} else {
  console.log('备份已存在，跳过');
}

let content = fs.readFileSync(actualPath, 'utf-8');
const before = content.length;

// UI replacements
const uiReplacements = {
  'New session': '新建会话',
  'New chat': '新对话',
  'New task': '新任务',
  'New code session': '新建代码会话',
  'New scheduled task': '新建计划任务',
  'Create with Claude': '使用 Claude 创建',
  'Go to home': '返回首页',
  'Previous step': '上一步',
  'Show more': '显示更多',
  'Add content from GitHub': '从 GitHub 添加内容',
  'Connect Claude to Google Drive': '将 Claude 连接到 Google 云端硬盘',
  'Change units': '更改单位',
  'Exit cooking mode': '退出烹饪模式',
  'Move to project': '移至项目',
  'Select a repository': '选择仓库',
  'Set up manually': '手动设置',
  'Sign in': '登录',
  'Try again': '重试',
  'Refresh': '刷新',
  'Filter scheduled tasks': '筛选计划任务',
  'Active': '活跃',
  'Draft': '草稿',
  'Free': '免费',
  'Owner': '所有者',
  'Admin': '管理员',
  'Primary Owner': '主要所有者',
  'User': '用户',
  'Request': '请求',
  'Dispatch': '分派',
  'Chats': '聊天',
  'Code': '代码',
  'Files': '文件',
  'Tasks': '任务',
  'Scheduled tasks': '计划任务',
  'Cowork': '协作',
  'Claude will return soon': 'Claude 即将返回',
  'Connecting to live monitor': '正在连接实时监控',
  'Placing call': '正在拨打电话',
  'Waiting for transcript': '等待转录',
  'Reading widget context': '读取小组件上下文',
  'Email digest': '电子邮件摘要',
  'Phone call': '电话',
  'Meeting prep': '会议准备',
  'Weekly review': '周回顾',
  'Code execution and file creation': '代码执行和文件创建',
  'Files hidden in shared chats': '在共享聊天中隐藏的文件',
  'Images hidden in shared chats': '在共享聊天中隐藏的图片',
  'Learn more about Anthropic': '了解更多关于 Anthropic 的信息',
  'A shared Claude Code onboarding guide': '共享的 Claude Code 入门指南',
  'Config preset': '配置预设',
  'Ignore Live Signals': '忽略实时信号',
  'Audio Description': '音频描述',
  'Switch to Claude Nest': '切换到 Claude Nest',
  'Sync Sources': '同步来源',
  'Welcome to Claude via AWS Marketplace': '欢迎通过 AWS Marketplace 使用 Claude',
  'Reset NUX': '重置新手引导',
  'Reset checklist state': '重置清单状态',
  'Force Show': '强制显示',
  'Description for the web search feature preview': '网页搜索功能预览的描述',
  'All Finance Skills': '所有金融技能',
  'Template Creator': '模板创建器',
  'Datapack Builder': '数据包构建器',
  'Deck Checker': '演示文稿检查器',
  'Company Profile': '公司概况',
  'Competitive Analysis': '竞争分析',
  'Pricing Analysis': '定价分析',
  'Earnings Analysis': '收益分析',
  'Comps Analysis': '可比分析',
  'DCF Valuation': 'DCF 估值',
  'Food Truck Business Plan': '餐车商业计划',
  'Initiating Coverage': '首次覆盖',
  'Pitch Deck': '路演演示',
  'Item Completion': '项目完成',
  'Weekly Metrics Review': '每周指标回顾',
};

let replaced = 0;

// Replace in UI property contexts
for (const [en, zh] of Object.entries(uiReplacements)) {
  const escaped = en.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const props = ['label', 'children', 'title', 'text', 'placeholder', 'tooltip', 'description', 'aria-label'];
  for (const prop of props) {
    const re = new RegExp(`(${prop}):"${escaped}"`, 'g');
    const m = content.match(re);
    if (m) {
      replaced += m.length;
      content = content.replace(re, `$1:"${zh}"`);
    }
  }
}

// Replace in defaultMessage fallback contexts
for (const [en, zh] of Object.entries(uiReplacements)) {
  const escaped = en.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(defaultMessage):"${escaped}"`, 'g');
  const m = content.match(re);
  if (m) {
    replaced += m.length;
    content = content.replace(re, `$1:"${zh}"`);
  }
}

fs.writeFileSync(actualPath, content, 'utf-8');
console.log(`\n完成: ${replaced} 处替换, ${before} -> ${content.length} 字节`);
