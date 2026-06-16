const fs = require('fs');
const path = require('path');

function findJsFiles() {
  const base = 'C:/Program Files/WindowsApps/';
  if (!fs.existsSync(base)) return null;
  const dirs = fs.readdirSync(base)
    .filter(d => d.startsWith('Claude_'))
    .sort()
    .reverse();
  for (const dir of dirs) {
    const p = path.join(base, dir, 'app/resources/ion-dist/assets/v1/');
    if (fs.existsSync(p)) {
      const files = fs.readdirSync(p).filter(f => f.endsWith('.js') && !f.endsWith('.bak') && fs.statSync(path.join(p, f)).size < 10 * 1024 * 1024);
      if (files.length > 0) return files.map(f => path.join(p, f));
    }
  }
  return null;
}

const jsFiles = findJsFiles();
if (!jsFiles) {
  console.error('找不到 ion-dist JS 文件');
  process.exit(1);
}

const reversals = [
  ['?"新任务":"新对话"', '?"New task":"New chat"'],
  ['||"新任务"', '||"New task"'],
  ['baseDescription:"新对话"', 'baseDescription:"New chat"'],
  ['baseDescription:"新任务"', 'baseDescription:"New task"'],
  ['recents:"最近",shared:"共享"', 'recents:"Recents",shared:"Shared"'],
  ['all:"全部",active:"活跃",archived:"已归档"', 'all:"All",active:"Active",archived:"Archived"'],
  ['all:"暂无任务。"', 'all:"No tasks yet."'],
  ['active:"没有活跃任务。"', 'active:"No active tasks."'],
  ['archived:"没有已归档任务。"', 'archived:"No archived tasks."'],
  ['recents:"暂无任务。"', 'recents:"No tasks yet."'],
  ['shared:"您还没有共享任何任务。"', "shared:\"You haven't shared any tasks yet.\""],
  ['noResults:"没有匹配的任务。"', 'noResults:"No tasks match your search."'],
  ['searchPlaceholder:"筛选任务"', 'searchPlaceholder:"Filter tasks"'],
  ['defaultMessage:"新建会话"', 'defaultMessage:"New session"'],
  ['defaultMessage:"新对话"', 'defaultMessage:"New chat"'],
  ['defaultMessage:"新任务"', 'defaultMessage:"New task"'],
  ['defaultMessage:"新建代码会话"', 'defaultMessage:"New code session"'],
  ['defaultMessage:"返回首页"', 'defaultMessage:"Go to home"'],
  ['defaultMessage:"电话"', 'defaultMessage:"Phone call"'],
  ['defaultMessage:"最近"', 'defaultMessage:"Recents"'],
  ['defaultMessage:"共享"', 'defaultMessage:"Shared"'],
  ['defaultMessage:"暂无任务。"', 'defaultMessage:"No tasks yet."'],
  ['defaultMessage:"没有活跃任务。"', 'defaultMessage:"No active tasks."'],
  ['defaultMessage:"没有已归档任务。"', 'defaultMessage:"No archived tasks."'],
  ['label:"新建会话"', 'label:"New session"'],
  ['label:"新对话"', 'label:"New chat"'],
  ['label:"新任务"', 'label:"New task"'],
  ['label:"新建代码会话"', 'label:"New code session"'],
  ['label:"返回首页"', 'label:"Go to home"'],
  ['label:"电话"', 'label:"Phone call"'],
  ['title:"新建会话"', 'title:"New session"'],
  ['title:"新对话"', 'title:"New chat"'],
  ['title:"新任务"', 'title:"New task"'],
  ['title:"返回首页"', 'title:"Go to home"'],
  ['placeholder:"新建会话"', 'placeholder:"New session"'],
  ['placeholder:"新对话"', 'placeholder:"New chat"'],
  ['placeholder:"新任务"', 'placeholder:"New task"'],
  ['code:"新建会话"', 'code:"New session"'],
  ['code:"新建代码会话"', 'code:"New code session"'],
  ['cowork:"新任务"', 'cowork:"New task"'],
  ['chat:"新对话"', 'chat:"New chat"'],
  ['children:"最近"', 'children:"Recents"'],
  ['newTask:{defaultMessage:"新任务"', 'newTask:{defaultMessage:"New task"'],
  ['newRoutine:{defaultMessage:"新建代码会话"', 'newRoutine:{defaultMessage:"New code session"'],
  // Global standalone strings (must be after specific patterns)
  ['"新建会话"', '"New session"'],
  ['"新对话"', '"New chat"'],
  ['"新任务"', '"New task"'],
  ['"新建代码会话"', '"New code session"'],
  ['"新建计划任务"', '"New scheduled task"'],
  ['"返回首页"', '"Go to home"'],
  ['"电话"', '"Phone call"'],
  ['"最近"', '"Recents"'],
  ['"共享"', '"Shared"'],
  ['"暂无任务。"', '"No tasks yet."'],
  ['"没有活跃任务。"', '"No active tasks."'],
  ['"没有已归档任务。"', '"No archived tasks."'],
  // Dev tools & settings
  ['"启用主进程调试器"', '"Enable Main Process Debugger"'],
  ['"记录性能跟踪"', '"Record Performance Trace"'],
  ['"写入主进程堆快照"', '"Write Main Process Heap Snapshot"'],
  ['"记录内存跟踪（自动停止）"', '"Record Memory Trace (auto-stop)"'],
  ['"推理配置"', '"Inference configuration"'],
  ['"查看更新日志"', '"View changelog"'],
  ['"重试。"', '"Try again."'],
];

let totalRestored = 0;

for (const jsFile of jsFiles) {
  const backupFile = jsFile + '.bak';

  // If backup exists, restore from backup (most reliable)
  if (fs.existsSync(backupFile)) {
    fs.copyFileSync(backupFile, jsFile);
    fs.unlinkSync(backupFile);
    console.log('从备份还原:', path.basename(jsFile));
    totalRestored++;
    continue;
  }

  // Otherwise, reverse-replace known patterns
  let content = fs.readFileSync(jsFile, 'utf-8');
  let changed = false;

  for (const [zh, en] of reversals) {
    if (content.includes(zh)) {
      content = content.split(zh).join(en);
      changed = true;
      totalRestored++;
    }
  }

  if (changed) {
    fs.writeFileSync(jsFile, content, 'utf-8');
    console.log('反向替换还原:', path.basename(jsFile));
  }
}

if (totalRestored > 0) {
  console.log(`共还原 ${totalRestored} 处`);
} else {
  console.log('未发现需要还原的硬编码字符串');
}
