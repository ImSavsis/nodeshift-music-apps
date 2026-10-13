import { Search } from 'lucide-react';

interface SearchBarProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  className?: string;
}

export function SearchBar({ value, onChange, placeholder = 'Поиск по трекам', className = '' }: SearchBarProps) {
  return (
    <div className={`flex items-center gap-2.5 rounded-pill border border-border2 bg-surface px-4 py-2.5 shadow-edge ${className}`}>
      <Search size={16} className="shrink-0 text-muted" />
      <input
        type="text"
        data-search
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
        className="w-full bg-transparent text-sm text-primary placeholder:text-dim focus:outline-none"
      />
    </div>
  );
}
