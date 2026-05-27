const fs = require('fs');
const path = require('path');

function findJsFile() {
  const base = 'C:/Program Files/WindowsApps/';
  if (!fs.existsSync(base)) return null;
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

const jsFile = findJsFile();
if (!jsFile) {
  console.error('找不到 ion-dist JS 文件');
  process.exit(1);
}

const backupFile = jsFile + '.bak';
if (!fs.existsSync(backupFile)) {
  console.error('备份文件不存在:', path.basename(backupFile));
  console.error('无法还原硬编码字符串补丁');
  process.exit(1);
}

fs.copyFileSync(backupFile, jsFile);
fs.unlinkSync(backupFile);
console.log('已还原:', path.basename(jsFile));
console.log('备份文件已删除');
