import { useMemo, useState } from 'react';
import { useStore } from '../data/store';
import type { ActivityType } from '../types';
import { ActivityFeed } from '../components/activity/ActivityFeed';
import { PageHeader } from '../components/ui/PageHeader';
import { Panel } from '../components/ui/Panel';
import { SelectField } from '../components/ui/SelectField';

const TYPE_OPTIONS = [
  { value: 'all', label: 'All activity types' },
  { value: 'status', label: 'Status changes' },
  { value: 'note', label: 'Administrative notes' },
];

function normalizeType(value: string): ActivityType | 'all' {
  if (value === 'status' || value === 'note') return value;
  return 'all';
}

export function ActivityPage() {
  const { activity } = useStore();
  const [type, setType] = useState('all');

  const filtered = useMemo(() => {
    const normalized = normalizeType(type);
    return [...activity]
      .sort((a, b) => b.at.localeCompare(a.at))
      .filter((item) => normalized === 'all' || item.type === normalized);
  }, [activity, type]);

  return (
    <>
      <PageHeader
        title="Activity"
        description="A chronological log of administrative actions recorded on reports, including changes you make in this session."
      />

      <Panel
        title="Administrative activity log"
        description="Newest entries first · derived from status changes and notes"
        action={
          <div className="w-56 max-w-full">
            <SelectField
              id="activity-type"
              label="Activity type"
              hideLabel
              value={type}
              onChange={setType}
              options={TYPE_OPTIONS}
            />
          </div>
        }
      >
        <p className="mb-4 text-xs text-slate-500" aria-live="polite">
          Showing {filtered.length} of {activity.length} entries
        </p>
        <ActivityFeed
          activity={filtered}
          emptyTitle="No activity matches this filter"
          emptyDescription="Choose a different activity type to see other status changes and notes."
        />
      </Panel>
    </>
  );
}
