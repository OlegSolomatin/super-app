#!/usr/bin/env python3
# Fix trading_page.dart — add 3rd OB tab
import sys

f = sys.argv[1]
lines = open(f).readlines()

# Fix 1: TabController length 2 -> 3
for i, l in enumerate(lines):
    if 'TabController(length: 2' in l:
        lines[i] = '    _tabController = TabController(length: 3, vsync: this);\n'
        print(f'Fix 1 done line {i}')
        break

# Fix 2: OB pill tab
for i, l in enumerate(lines):
    if 'label:' in l and ' OB' in l:
        # Find the opening if block
        start = None
        for j in range(i, max(i-8, 0), -1):
            if '_obRuns.isNotEmpty' in lines[j]:
                start = j
                break
        if start is None:
            print(f'Could not find start for pill at line {i}')
            continue
        # Find end - closing ],
        end = i + 6
        for j in range(i, min(i+8, len(lines))):
            if '],' in lines[j] and '],' not in lines[j-1]:
                end = j + 1
                break
        print(f'Fix 2: replacing lines {start}-{end}')
        replace = [
            '                  const SizedBox(width: 2),\n',
            '                  _PillTab(\n',
            "                    label: '\U0001f4d7 OB',\n",
            '                    count: _obRuns.length,\n',
            '                    isActive: _tabController.index == 2,\n',
            "                    onTap: () => _tabController.animateTo(2),\n",
            '                  ),\n',
        ]
        lines = lines[:start] + replace + lines[end:]
        break

# Fix 3: TabBarView - add _buildObRunsList
for i, l in enumerate(lines):
    if 'emptySubtext' in l and 'repository: widget.repository' in lines[min(i+2, len(lines)-1)]:
        # Find the closing ),
        for j in range(i, min(i+6, len(lines))):
            if '),' in lines[j]:
                lines.insert(j+1, '                  _buildObRunsList(),\n')
                print(f'Fix 3 done at line {j+1}')
                break
        break

# Fix 4: Insert _buildObRunsList method before _ModeCard
for i, l in enumerate(lines):
    if 'class _ModeCard extends StatelessWidget' in l:
        method = [
            '\n',
            '  // \u2500\u2500 OrderBook Runs List\n',
            '  Widget _buildObRunsList() {\n',
            '    final pc = PfColors.of(context);\n',
            '    if (_loadingObRuns) {\n',
            '      return const Center(child: CircularProgressIndicator());\n',
            '    }\n',
            '    if (_obRuns.isEmpty) {\n',
            '      return Center(\n',
            '        child: Column(\n',
            '          mainAxisSize: MainAxisSize.min,\n',
            '          children: [\n',
            '            PhosphorIcon(\n',
            '              PhosphorIconsFill.stack,\n',
            '              size: 48,\n',
            '              color: pc.mutedForegroundC.withValues(alpha: 0.3),\n',
            '            ),\n',
            '            const SizedBox(height: 16),\n',
            '            Text(\n',
            "              '\u041d\u0435\u0442 OB-\u0437\u0430\u043f\u0443\u0441\u043a\u043e\u0432',\n",
            '              style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC),\n',
            '            ),\n',
            '            const SizedBox(height: 4),\n',
            '            Text(\n',
            "              '\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u0435 \u0441\u0442\u0440\u0430\u0442\u0435\u0433\u0438\u044e \u043f\u043e \u043e\u0440\u0434\u0435\u0440\u0431\u0443\u043a\u0443',\n",
            '              style: PfTypography.bodySm.copyWith(\n',
            '                color: pc.mutedForegroundC.withValues(alpha: 0.6),\n',
            '              ),\n',
            '            ),\n',
            '          ],\n',
            '        ),\n',
            '      );\n',
            '    }\n',
            '    return RefreshIndicator(\n',
            '      onRefresh: _loadOrderBookRuns,\n',
            '      child: ListView.separated(\n',
            '        padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),\n',
            '        itemCount: _obRuns.length,\n',
            '        separatorBuilder: (_, __) => const SizedBox(height: PfSpacing.sm),\n',
            '        itemBuilder: (context, index) {\n',
            '          final run = _obRuns[index];\n',
            '          final status = run[\'status\'] as String? ?? \'unknown\';\n',
            '          final pair = run[\'pair\'] as String? ?? \'N/A\';\n',
            '          final strategy = run[\'strategy\'] as String? ?? \'N/A\';\n',
            '          return PfCard(\n',
            '            padding: const EdgeInsets.symmetric(\n',
            '              horizontal: PfSpacing.md, vertical: PfSpacing.sm,\n',
            '            ),\n',
            '            child: Row(\n',
            '              children: [\n',
            '                Container(\n',
            '                  width: 40,\n',
            '                  height: 40,\n',
            '                  decoration: BoxDecoration(\n',
            '                    color: status == \'running\'\n',
            '                        ? PfColors.success.withValues(alpha: 0.12)\n',
            '                        : pc.mutedC,\n',
            '                    borderRadius: PfRadius.borderRadiusMd,\n',
            '                  ),\n',
            '                  child: Center(\n',
            '                    child: PhosphorIcon(\n',
            '                      status == \'running\'\n',
            '                          ? PhosphorIconsFill.playCircle\n',
            '                          : PhosphorIconsFill.checkCircle,\n',
            '                      size: 20,\n',
            '                      color: status == \'running\'\n',
            '                          ? PfColors.success\n',
            '                          : pc.mutedForegroundC,\n',
            '                    ),\n',
            '                  ),\n',
            '                ),\n',
            '                const SizedBox(width: 12),\n',
            '                Expanded(\n',
            '                  child: Column(\n',
            '                    crossAxisAlignment: CrossAxisAlignment.start,\n',
            '                    children: [\n',
            '                      Text(\n',
            '                        pair,\n',
            '                        style: PfTypography.titleMd.copyWith(\n',
            '                          color: pc.foregroundC,\n',
            '                          fontWeight: FontWeight.w600,\n',
            '                        ),\n',
            '                      ),\n',
            '                      const SizedBox(height: 2),\n',
            '                      Text(\n',
            '                        \'$strategy \u00b7 ${status == \'running\' ? \'\U0001f7e0 \u0410\u043a\u0442\u0438\u0432\u043d\u0430\' : \'\u23f9\ufe0f \u0417\u0430\u0432\u0435\u0440\u0448\u0435\u043d\u0430\'}\',\n',
            '                        style: PfTypography.bodySm.copyWith(\n',
            '                          color: pc.mutedForegroundC,\n',
            '                        ),\n',
            '                      ),\n',
            '                    ],\n',
            '                  ),\n',
            '                ),\n',
            '                if (status == \'running\')\n',
            '                  PfButton(\n',
            "                    variant: 'outline',\n",
            "                    size: 'sm',\n",
            "                    label: '\u23f9',\n",
            '                    onPressed: () async {\n',
            '                      final id = run[\'id\'] as int?;\n',
            '                      if (id != null) {\n',
            '                        await _repository.stopOrderBookRun(id);\n',
            '                        _loadOrderBookRuns();\n',
            '                      }\n',
            '                    },\n',
            '                  ),\n',
            '              ],\n',
            '            ),\n',
            '          );\n',
            '        },\n',
            '      ),\n',
            '    );\n',
            '  }\n',
            '\n',
        ]
        lines = lines[:i] + method + lines[i:]
        print(f'Fix 4 done before line {i}')
        break

open(f, 'w').writelines(lines)
print('All fixes applied')
