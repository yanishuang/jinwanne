const rowsElement = document.querySelector('#ranking-rows');
const stateElement = document.querySelector('#board-state');
const rangeElement = document.querySelector('#range-label');
const countElement = document.querySelector('#participant-count');
const metricButtons = [...document.querySelectorAll('[data-metric]')];
const periodButtons = [...document.querySelectorAll('[data-period]')];
let metric = 'success';
let period = 'month';
let requestNumber = 0;

const periodNames = { month: '本月', year: '今年', all: '全部时间' };

function setSelected(buttons, selected, attribute) {
  for (const button of buttons) {
    const active = button.dataset[attribute] === selected;
    button.classList.toggle('active', active);
    if (attribute === 'metric') button.setAttribute('aria-selected', String(active));
  }
}

function renderRows(rows) {
  rowsElement.replaceChildren(...rows.map(row => {
    const tr = document.createElement('tr');
    const rank = document.createElement('td');
    const alias = document.createElement('td');
    const days = document.createElement('td');
    rank.textContent = String(row.rank).padStart(2, '0');
    alias.textContent = row.alias;
    days.textContent = `${row.days} 天`;
    tr.append(rank, alias, days);
    return tr;
  }));
}

async function loadRanking() {
  const currentRequest = ++requestNumber;
  stateElement.hidden = false;
  stateElement.textContent = '正在读取排行榜…';
  rowsElement.replaceChildren();
  countElement.textContent = '';
  try {
    const response = await fetch(`/api/leaderboard?metric=${metric}&period=${period}`, { cache: 'no-store' });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || '读取失败');
    if (currentRequest !== requestNumber) return;
    rangeElement.textContent = `${periodNames[period]} · ${data.start} 至 ${data.end}`;
    countElement.textContent = `${data.total} 人参与`;
    renderRows(data.rows);
    stateElement.hidden = data.rows.length > 0;
    stateElement.textContent = data.rows.length ? '' : '这个榜单还没有人参与';
  } catch {
    if (currentRequest !== requestNumber) return;
    rangeElement.textContent = periodNames[period];
    stateElement.hidden = false;
    stateElement.textContent = '排行榜暂时无法读取，请稍后刷新';
  }
}

for (const button of metricButtons) {
  button.addEventListener('click', () => {
    metric = button.dataset.metric;
    setSelected(metricButtons, metric, 'metric');
    loadRanking();
  });
}
for (const button of periodButtons) {
  button.addEventListener('click', () => {
    period = button.dataset.period;
    setSelected(periodButtons, period, 'period');
    loadRanking();
  });
}

loadRanking();
