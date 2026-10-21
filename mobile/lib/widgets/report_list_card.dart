import 'package:flutter/material.dart';

import '../models/civic_report.dart';
import '../utils/report_format.dart';
import 'report_status_chip.dart';
import 'report_thumbnail.dart';

const Color _navy = Color(0xFF102A43);
const Color _muted = Color(0xFF627D98);
const Color _border = Color(0xFFE4EAF0);

/// Reusable list row for a report.
class ReportListCard extends StatelessWidget {
  const ReportListCard({
    super.key,
    required this.report,
    required this.onTap,
    this.trailing,
  });

  final CivicReport report;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReportThumbnail(report: report, size: 58),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.category.toUpperCase(),
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      report.title,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: _muted,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            displayLocationName(report),
                            style: const TextStyle(color: _muted, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (report.landmarkOrNull != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.near_me_outlined,
                            size: 13,
                            color: _muted,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              report.landmarkOrNull!,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      formatDate(report.createdAt),
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ReportStatusChip(status: report.status, dense: true),
                        const Spacer(),
                        trailing ??
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 13,
                              color: _muted,
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
