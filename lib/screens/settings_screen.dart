// Ayarlar ekranı
// Acil kişi yönetimi, mesaj şablonu, Twilio sandbox aktivasyonu, hesap

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/emergency_contact.dart';
import '../services/contact_service.dart';
import '../services/firestore_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ContactService _contactService = ContactService();
  final FirestoreService _firestoreService = FirestoreService();

  // Ayar form kontrolcüleri
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _callerNameController = TextEditingController();

  // Acil kişiler listesi
  List<EmergencyContact> _contacts = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadContacts();
  }

  Future<void> _loadSettings() async {
    final settings = await _firestoreService.getSettings();
    _messageController.text = settings['message'] ?? '';
    _callerNameController.text = settings['callerName'] ?? '';
  }

  Future<void> _loadContacts() async {
    _firestoreService.watchContacts().listen((contacts) {
      if (mounted) setState(() => _contacts = contacts);
    });
  }

  // ─────────────────────────────────────────────
  // Ayarları kaydet
  // ─────────────────────────────────────────────
  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await _firestoreService.updateSettings({
        'message': _messageController.text.trim(),
        'callerName': _callerNameController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ayarlar kaydedildi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─────────────────────────────────────────────
  // Rehberden kişi ekle
  // ─────────────────────────────────────────────
  Future<void> _addContact() async {
    try {
      final phoneContact = await _contactService.pickContact();
      if (phoneContact == null) return;

      // Kanal seçim dialogu göster
      final selectedChannels = await showDialog<List<ContactChannel>>(
        context: context,
        builder: (ctx) => _ChannelPickerDialog(contactName: phoneContact.displayName),
      );

      if (selectedChannels == null || selectedChannels.isEmpty) return;

      await _contactService.saveContactFromPhone(
        phoneContact,
        channels: selectedChannels,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${phoneContact.displayName} eklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kişi eklenemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  // Kişiyi sil
  // ─────────────────────────────────────────────
  Future<void> _deleteContact(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kişiyi Sil'),
        content: Text('${contact.name} acil kişi listesinden silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _contactService.deleteContact(contact.id);
    }
  }

  // ─────────────────────────────────────────────
  // Kanal düzenleme
  // ─────────────────────────────────────────────
  Future<void> _editChannels(EmergencyContact contact) async {
    final selectedChannels = await showDialog<List<ContactChannel>>(
      context: context,
      builder: (ctx) => _ChannelPickerDialog(
        contactName: contact.name,
        initialChannels: contact.channels,
      ),
    );

    if (selectedChannels != null) {
      await _contactService.updateContactChannels(contact.id, selectedChannels);
    }
  }

  // ─────────────────────────────────────────────
  // Twilio Sandbox aktivasyon linkini aç
  // ─────────────────────────────────────────────
  Future<void> _openTwilioSandbox() async {
    // WhatsApp sandbox aktivasyonu için Twilio join linki
    final Uri waUri = Uri.parse('https://wa.me/+14155238886?text=join%20your-sandbox-word');
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    }
  }

  // ─────────────────────────────────────────────
  // Google ile giriş/çıkış
  // ─────────────────────────────────────────────
  Future<void> _signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Ayarlar',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Kaydet butonu
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Kaydet',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Mesaj şablonu ──
          _SectionHeader(title: 'Acil Mesaj', icon: Icons.message),
          const SizedBox(height: 8),
          _DarkTextField(
            controller: _messageController,
            hint: 'ACİL YARDIM! Yardıma ihtiyacım var.',
            maxLines: 3,
            label: 'Mesaj şablonu',
          ),
          const SizedBox(height: 8),
          _DarkTextField(
            controller: _callerNameController,
            hint: 'Ad Soyad',
            label: 'Adınız (aramalarda kullanılır)',
          ),

          const SizedBox(height: 24),

          // ── Acil kişiler ──
          Row(
            children: [
              const _SectionHeader(title: 'Acil Kişiler', icon: Icons.contacts),
              const Spacer(),
              FilledButton.icon(
                onPressed: _addContact,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ekle'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE63946),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Kişi sayısı uyarısı
          if (_contacts.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Acil kişi eklenmemiş. "Ekle" butonuna basarak rehberden kişi seçin.',
                      style: TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Sürükle-bırak kişi listesi
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _contacts.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _contacts.removeAt(oldIndex);
                _contacts.insert(newIndex, item);
              });
              _contactService.reorderContacts(_contacts);
            },
            itemBuilder: (ctx, i) {
              final contact = _contacts[i];
              return _ContactEditTile(
                key: ValueKey(contact.id),
                contact: contact,
                onEditChannels: () => _editChannels(contact),
                onDelete: () => _deleteContact(contact),
              );
            },
          ),

          const SizedBox(height: 24),

          // ── Twilio Sandbox ──
          _SectionHeader(title: 'WhatsApp Aktivasyonu', icon: Icons.chat),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Twilio Sandbox ile WhatsApp mesajı alabilmek için her kişinin '
                  'aşağıdaki adımı tamamlaması gerekiyor:',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'WhatsApp\'tan +1 415 523 8886 numarasına\n"join [sandbox-kelimesi]" mesajı gönder',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openTwilioSandbox,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('WhatsApp\'ta Aç'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Hesap ──
          _SectionHeader(title: 'Hesap', icon: Icons.account_circle),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Profil fotoğrafı
                CircleAvatar(
                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,
                  child: user?.photoURL == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 12),
                // Kullanıcı bilgileri
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? 'Kullanıcı',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Çıkış butonu
                TextButton(
                  onPressed: _signOut,
                  child: const Text(
                    'Çıkış',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _callerNameController.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────
// Kanal seçim dialogu
// ─────────────────────────────────────────────
class _ChannelPickerDialog extends StatefulWidget {
  final String contactName;
  final List<ContactChannel> initialChannels;

  const _ChannelPickerDialog({
    required this.contactName,
    this.initialChannels = const [ContactChannel.notification],
  });

  @override
  State<_ChannelPickerDialog> createState() => _ChannelPickerDialogState();
}

class _ChannelPickerDialogState extends State<_ChannelPickerDialog> {
  late List<ContactChannel> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialChannels);
  }

  void _toggle(ContactChannel channel) {
    setState(() {
      if (_selected.contains(channel)) {
        _selected.remove(channel);
      } else {
        _selected.add(channel);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.contactName} — Kanallar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChannelCheckTile(
            icon: Icons.notifications,
            label: 'Bildirim',
            sublabel: 'FCM push notification',
            value: _selected.contains(ContactChannel.notification),
            onChanged: (_) => _toggle(ContactChannel.notification),
          ),
          _ChannelCheckTile(
            icon: Icons.chat,
            label: 'WhatsApp',
            sublabel: 'Twilio WhatsApp mesajı',
            value: _selected.contains(ContactChannel.whatsapp),
            onChanged: (_) => _toggle(ContactChannel.whatsapp),
          ),
          _ChannelCheckTile(
            icon: Icons.phone,
            label: 'Telefon Araması',
            sublabel: 'Twilio sesli arama',
            value: _selected.contains(ContactChannel.call),
            onChanged: (_) => _toggle(ContactChannel.call),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Tamam'),
        ),
      ],
    );
  }
}

class _ChannelCheckTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _ChannelCheckTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      secondary: Icon(icon),
      title: Text(label),
      subtitle: Text(sublabel, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }
}

// ─────────────────────────────────────────────
// Düzenlenebilir kişi kartı
// ─────────────────────────────────────────────
class _ContactEditTile extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onEditChannels;
  final VoidCallback onDelete;

  const _ContactEditTile({
    super.key,
    required this.contact,
    required this.onEditChannels,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Sürükleme tutacağı
          const Icon(Icons.drag_handle, color: Colors.white30),
          const SizedBox(width: 8),

          // Avatar
          CircleAvatar(
            backgroundColor: const Color(0xFFE63946).withOpacity(0.3),
            radius: 18,
            child: Text(
              contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Color(0xFFE63946),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // İsim ve kanallar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                // Kanal chipleri
                Wrap(
                  spacing: 4,
                  children: [
                    if (contact.hasChannel(ContactChannel.notification))
                      _ChannelChip(label: 'Bildirim', color: Colors.blue),
                    if (contact.hasChannel(ContactChannel.whatsapp))
                      _ChannelChip(label: 'WA', color: const Color(0xFF25D366)),
                    if (contact.hasChannel(ContactChannel.call))
                      _ChannelChip(label: 'Arama', color: Colors.orange),
                  ],
                ),
              ],
            ),
          ),

          // Düzenle butonu
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
            onPressed: onEditChannels,
            tooltip: 'Kanalları düzenle',
          ),

          // Sil butonu
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: onDelete,
            tooltip: 'Sil',
          ),
        ],
      ),
    );
  }
}

/// Küçük kanal etiketi
class _ChannelChip extends StatelessWidget {
  final String label;
  final Color color;

  const _ChannelChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Yardımcı widget'lar
// ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFE63946), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String label;
  final int maxLines;

  const _DarkTextField({
    required this.controller,
    required this.hint,
    required this.label,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE63946)),
        ),
      ),
    );
  }
}
