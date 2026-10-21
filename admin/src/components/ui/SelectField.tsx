import { cn } from '../../lib/cn';
import { labelClass, selectClass } from '../../lib/styles';
import { IconChevronDown } from './Icon';

export interface SelectOption {
  value: string;
  label: string;
}

export function SelectField({
  id,
  label,
  value,
  options,
  onChange,
  hideLabel,
  className,
  disabled,
}: {
  id: string;
  label: string;
  value: string;
  options: SelectOption[];
  onChange: (value: string) => void;
  hideLabel?: boolean;
  className?: string;
  disabled?: boolean;
}) {
  return (
    <div className={className}>
      <label htmlFor={id} className={cn(labelClass, hideLabel && 'sr-only')}>
        {label}
      </label>
      <div className="relative">
        <select
          id={id}
          value={value}
          disabled={disabled}
          onChange={(event) => onChange(event.target.value)}
          className={selectClass}
        >
          {options.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
        <IconChevronDown
          size={16}
          className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-slate-400"
        />
      </div>
    </div>
  );
}
