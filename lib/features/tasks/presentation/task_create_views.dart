part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TaskCreateViews on _CreateTaskPageState {

  Widget _buildView(BuildContext context) {
    final spacing = context.appSpacing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yangi vazifa'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Saqlash'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(spacing.md),
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: true,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Vazifa nomi',
                  hintText: 'Masalan: Haftalik hisobotni tayyorlash',
                ),
                validator: (value) => value?.trim().isEmpty == true
                    ? 'Vazifa nomini kiriting'
                    : null,
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _descriptionController,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Vazifa tafsiloti',
                  hintText:
                      'Nima qilish kerakligi va kutilayotgan natijani yozing',
                  alignLabelWithHint: true,
                ),
              ),
              SizedBox(height: spacing.lg),
              Text('Bajaruvchi', style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: spacing.xs),
              DropdownButtonFormField<int>(
                initialValue: _assigneeId,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                items: _uniqueAssignees.map((member) {
                  final name = member['name'] as String? ?? 'Xodim';
                  final role =
                      member['role_name'] as String? ?? 'Lavozim belgilanmagan';
                  return DropdownMenuItem<int>(
                    value: (member['member_id'] as num).toInt(),
                    child: Row(
                      children: [
                        AppAvatar(
                          label: name,
                          imageUrl: member['avatar_url'] as String?,
                          radius: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, overflow: TextOverflow.ellipsis),
                              Text(
                                role,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _assigneeId = value),
                validator: (_) =>
                    _assigneeId == null ? 'Bajaruvchini tanlang' : null,
              ),
              SizedBox(height: spacing.lg),
              Text(
                'Muhimlik va muddat',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: spacing.xs),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.flag_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Past')),
                        DropdownMenuItem(value: 'normal', child: Text('Oddiy')),
                        DropdownMenuItem(value: 'high', child: Text('Yuqori')),
                        DropdownMenuItem(
                          value: 'urgent',
                          child: Text('Shoshilinch'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _priority = value ?? 'normal'),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDeadline,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _dueAt == null ? 'Deadline' : _formatDate(_dueAt!),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    allowMultiple: true,
                    withData: true,
                  );
                  if (result != null && result.files.isNotEmpty) {
                    final selected = result.files.where(
                      (file) => file.size > 0,
                    );
                    final existing = _attachments
                        .map((file) => '${file.name}:${file.size}')
                        .toSet();
                    final added = selected
                        .where(
                          (file) => existing.add('${file.name}:${file.size}'),
                        )
                        .toList();
                    if (added.isNotEmpty) {
                      setState(
                        () => _attachments = [..._attachments, ...added],
                      );
                    }
                  }
                },
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(
                  _attachments.isEmpty
                      ? 'Fayllar biriktirish (ixtiyoriy)'
                      : '${_attachments.length} ta fayl tanlangan',
                ),
              ),
              if (_attachments.isNotEmpty) ...[
                SizedBox(height: spacing.xs),
                ..._attachments.asMap().entries.map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(
                      entry.value.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_formatBytes(entry.value.size)),
                    trailing: IconButton(
                      tooltip: 'Olib tashlash',
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _attachments = [
                                ..._attachments.sublist(0, entry.key),
                                ..._attachments.sublist(entry.key + 1),
                              ],
                            ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ],
              if (_saving) ...[
                SizedBox(height: spacing.md),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }


}
