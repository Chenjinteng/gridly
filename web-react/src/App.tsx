// Design Demo: 3 套候选,?A/?B/?C 切换
// 配色 + 字体不同,布局/UX 相同
// 跑 `npm run dev` 浏览器开 http://localhost:5173/?a / ?b / ?c
import { useSearchParams } from 'react-router-dom';
import DemoA from './demos/DemoA';
import DemoB from './demos/DemoB';
import DemoC from './demos/DemoC';

export default function App() {
  const [params] = useSearchParams();
  const variant = (params.get('demo') || 'a').toLowerCase();
  if (variant === 'b') return <DemoB />;
  if (variant === 'c') return <DemoC />;
  return <DemoA />;
}