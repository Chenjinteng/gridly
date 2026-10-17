// gridly LOGO — 3 个倾斜方块(黑/黄/绿)
// 从 assets/images/logo/logo_primary.png + logo_reverse.png 还原
// - viewBox 120x120
// - 三个 48x48 圆角方块,各自 rotate -8°
// - 黑色方块 light=#1A1A1A / dark=#F5F5F7(自动)
// - 黄 #EAB308 / 绿 #10B981 始终
// - cascade 排列:TL + TR(略高)/ BR(略低)

interface Props {
  size?: number;
  mode?: 'light' | 'dark';
  title?: string;
}

export function Logo({ size = 24, mode = 'light', title = 'gridly' }: Props) {
  const tl = mode === 'dark' ? '#F5F5F7' : '#1A1A1A';
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 120 120"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label={title}
      style={{ display: 'block' }}
    >
      <title>{title}</title>
      <g transform="rotate(-8 60 60)">
        <rect x="14" y="30" width="48" height="48" rx="7" fill={tl} />
        <rect x="58" y="22" width="48" height="48" rx="7" fill="#EAB308" />
        <rect x="58" y="62" width="48" height="48" rx="7" fill="#10B981" />
      </g>
    </svg>
  );
}