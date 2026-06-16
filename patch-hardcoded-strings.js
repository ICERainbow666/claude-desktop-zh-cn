const fs = require('fs');
const path = require('path');

function findJsFile() {
  const base = 'C:/Program Files/WindowsApps/';
  if (!fs.existsSync(base)) return null;
  const dirs = fs.readdirSync(base)
    .filter(d => d.startsWith('Claude_'))
    .sort()
    .reverse(); // latest version first
  for (const dir of dirs) {
    const p = path.join(base, dir, 'app/resources/ion-dist/assets/v1/');
    if (fs.existsSync(p)) {
      const files = fs.readdirSync(p).filter(f => f.endsWith('.js') && !f.endsWith('.bak') && fs.statSync(path.join(p, f)).size < 10 * 1024 * 1024);
      if (files.length > 0) return path.join(p, files[0]);
    }
  }
  return null;
}

const actualPath = findJsFile();
if (!actualPath) {
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
  'Filter scheduled tasks': '筛选计划任务',
  'Primary Owner': '主要所有者',
  'Scheduled tasks': '计划任务',
  'Claude will return soon': 'Claude 即将返回',
  'Connecting to live monitor': '正在连接实时监控',
  'Placing call': '正在拨打电话',
  'Waiting for transcript': '等待转录',
  'Reading widget context': '读取小组件上下文',
  'Email digest': '电子邮件摘要',
  'Phone call': '电话',
  'Meeting prep': '会议准备',
  'Recents': '最近',
  'Shared': '共享',
  'No tasks yet.': '暂无任务。',
  'No active tasks.': '没有活跃任务。',
  'No archived tasks.': '没有已归档任务。',
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
  'No tasks yet.': '暂无任务。',
  'No active tasks.': '没有活跃任务。',
  'No archived tasks.': '没有已归档任务。',
  'Recents': '最近',
  'Someone gifted you Claude': '有人赠送了您 Claude',
  "Couldn't send your request.": '无法发送您的请求。',
  "Couldn't rename this task.": '无法重命名此任务。',
  "Couldn't archive this task.": '无法归档此任务。',
  "Couldn't delete this task.": '无法删除此任务。',
  'Something went wrong while deleting.': '删除时出错。',
  'Refresh the page and try again': '请刷新页面后重试',
};

let replaced = 0;

// Phase 1: Replace in UI property contexts (label, children, title, etc.)
for (const [en, zh] of Object.entries(uiReplacements)) {
  const escaped = en.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const props = ['label', 'children', 'title', 'text', 'placeholder', 'tooltip', 'description', 'aria-label'];
  for (const prop of props) {
    const re = new RegExp(`(${prop}):\\s*"${escaped}"`, 'g');
    const m = content.match(re);
    if (m) {
      replaced += m.length;
      content = content.replace(re, `$1:"${zh}"`);
    }
  }
}

// Phase 2: Replace in defaultMessage fallback contexts
for (const [en, zh] of Object.entries(uiReplacements)) {
  const escaped = en.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(defaultMessage):"${escaped}"`, 'g');
  const m = content.match(re);
  if (m) {
    replaced += m.length;
    content = content.replace(re, `$1:"${zh}"`);
  }
}

// Phase 3: Replace hardcoded strings inside ternary expressions and other complex contexts
// These strings bypass the i18n system and need direct string replacement
const directReplacements = [
  // Sidebar button ternary: "cowork"===s?"New task":"New chat"
  { pattern: '?"New task":"New chat"', replacement: '?"新任务":"新对话"' },
  // Default title fallback: ||"New task"
  { pattern: '||"New task"', replacement: '||"新任务"' },
  // Command palette baseDescription
  { pattern: 'baseDescription:"New chat"', replacement: 'baseDescription:"新对话"' },
  { pattern: 'baseDescription:"New task"', replacement: 'baseDescription:"新任务"' },
  // sessionData second arg: RQ(t,s,"New task")
  { pattern: 'RQ(t,s,"New task")', replacement: 'RQ(t,s,"新任务")' },
  // Tab filter map objects
  { pattern: 'all:"All",active:"Active",archived:"Archived"', replacement: 'all:"全部",active:"活跃",archived:"已归档"' },
  // Error messages with "Try again"
  { pattern: 'Try again.",{error:t})', replacement: '重试。",{error:t})' },
  { pattern: 'Try again.",{error:e})', replacement: '重试。",{error:e})' },
  { pattern: 'Refresh the page and try again",{', replacement: '请刷新页面后重试",{ ' },
  // Organization sign-in error
  { pattern: 'Sign in and try again."', replacement: '请登录后重试。"' },
  // Ternary with "Recents" in sidebar
  { pattern: 'recents:"Recents",shared:"Shared"', replacement: 'recents:"最近",shared:"共享"' },
  // Free/Pro/Max plan labels in ternary
  { pattern: '?"Pro":s.capabilities.includes("claude_max")?"Max":"Free"', replacement: '?"Pro":s.capabilities.includes("claude_max")?"Max":"免费"' },
  // Empty state messages for task tabs
  { pattern: 'all:"No tasks yet."', replacement: 'all:"暂无任务。"' },
  { pattern: 'active:"No active tasks."', replacement: 'active:"没有活跃任务。"' },
  { pattern: 'archived:"No archived tasks."', replacement: 'archived:"没有已归档任务。"' },
  // More empty state patterns
  { pattern: 'recents:"No tasks yet."', replacement: 'recents:"暂无任务。"' },
  { pattern: 'shared:"You haven\'t shared any tasks yet."', replacement: 'shared:"您还没有共享任何任务。"' },
  { pattern: 'noResults:"No tasks match your search."', replacement: 'noResults:"没有匹配的任务。"' },
  { pattern: 'searchPlaceholder:"Filter tasks"', replacement: 'searchPlaceholder:"筛选任务"' },
  // code/cowork/chat property context
  { pattern: 'code:"New session"', replacement: 'code:"新建会话"' },
  { pattern: 'code:"New code session"', replacement: 'code:"新建代码会话"' },
  { pattern: 'cowork:"New task"', replacement: 'cowork:"新任务"' },
  { pattern: 'chat:"New chat"', replacement: 'chat:"新对话"' },
  { pattern: 'children:"Recents"', replacement: 'children:"最近"' },
];

for (const { pattern, replacement } of directReplacements) {
  if (pattern === replacement) continue; // skip no-op
  const m = content.match(new RegExp(pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'));
  if (m) {
    replaced += m.length;
    content = content.replaceAll(pattern, replacement);
  }
}

fs.writeFileSync(actualPath, content, 'utf-8');
console.log(`\n完成: ${replaced} 处替换, ${before} -> ${content.length} 字节`);
