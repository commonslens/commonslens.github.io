import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

const _sourceUrl = 'https://github.com/commonslens/commonslens.github.io';
const _licenseFileUrl =
    'https://github.com/commonslens/commonslens.github.io/blob/master/LICENSE';
const _apacheLicenseUrl = 'https://www.apache.org/licenses/LICENSE-2.0';
const _commonsReuseUrl =
    'https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia';
const _wikimediaTermsUrl =
    'https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use';
const _wikimediaPrivacyUrl =
    'https://foundation.wikimedia.org/wiki/Policy:Privacy_policy';
const _wikimediaApiUrl =
    'https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_API_Usage_Guidelines';
const _githubPrivacyUrl =
    'https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement';
const _osmPrivacyUrl = 'https://osmfoundation.org/wiki/Privacy_Policy';
const _esriPrivacyUrl =
    'https://www.esri.com/en-us/privacy/privacy-statements/privacy-statement';

Future<void> _openExternal(String url) async {
  await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_blank',
  );
}

/// Shared footer for public, indexable pages and the main landing page.
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key, this.showDivider = true});

  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFF242424)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              _FooterLink(
                label: 'Terms of Use',
                onPressed: () => context.go('/terms'),
              ),
              _FooterLink(
                label: 'Privacy Policy',
                onPressed: () => context.go('/privacy'),
              ),
              _FooterLink(
                label: 'Source code',
                icon: Icons.open_in_new,
                onPressed: () => _openExternal(_sourceUrl),
              ),
              _FooterLink(
                label: 'Apache 2.0',
                icon: Icons.open_in_new,
                onPressed: () => _openExternal(_licenseFileUrl),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon == null
          ? const SizedBox.shrink()
          : Icon(icon, size: 13, color: const Color(0xFF777777)),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF999999),
        textStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      ),
    );
  }
}

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalPageScaffold(
      eyebrow: 'TERMS OF USE',
      title: 'Use CommonsLens responsibly',
      summary:
          'CommonsLens helps you find and understand reusable media, but every file keeps its own licence and attribution requirements. You—not CommonsLens—are responsible for checking and following them.',
      sections: [
        const _LegalSection(
          title: '1. Agreement and scope',
          paragraphs: [
            'These Terms apply when you use the CommonsLens website, search tools, map, media viewer, downloads, exports, or visual pipelines. By using the service, you agree to these Terms. If you do not agree, please do not use CommonsLens.',
            'CommonsLens is an independent interface to public Wikimedia services. It is not operated, sponsored, endorsed, or warranted by the Wikimedia Foundation, Wikimedia Commons, Wikidata, OpenStreetMap, Esri, Google, or GitHub.',
          ],
        ),
        _LegalSection(
          title: '2. Media licences and attribution—your responsibility',
          paragraphs: [
            'CommonsLens does not own the files it displays and does not grant you a new licence. Downloading a file does not mean that it is unrestricted or free of obligations.',
            'You MUST follow every attribution, credit, source-link, licence notice, share-alike, modification disclosure, author-requested credit line, and other reuse requirement set by the file’s licence, its Wikimedia Commons description page, and its author or other rightsholder. If CommonsLens shows incomplete or conflicting information, the original file page and the applicable licence control.',
          ],
          bullets: const [
            'Open the original Commons file page before publishing or distributing a file.',
            'Credit the creator—not merely the uploader—unless the source specifically says otherwise.',
            'Name or link the licence when required and indicate modifications when required.',
            'Apply the same or a compatible licence to derivatives when a share-alike licence requires it.',
            'Do not remove credit, rights statements, watermarks, or notices in a way the licence forbids.',
          ],
          links: const [
            _PolicyLink('Official Wikimedia reuse guidance', _commonsReuseUrl),
            _PolicyLink(
                'Wikimedia Foundation Terms of Use', _wikimediaTermsUrl),
          ],
        ),
        const _LegalSection(
          title: '3. Rights beyond copyright',
          paragraphs: [
            'A free copyright licence does not clear every possible use. Images and metadata may still involve privacy, publicity or personality rights, moral rights, trademarks, patents, cultural restrictions, contractual restrictions, sensitive subjects, or laws that differ by country. Commercial, advertising, political, medical, or defamatory contexts can need extra care or permission.',
            'CommonsLens summaries, filters, warnings, and generated attribution snippets are conveniences, not legal advice or a guarantee that a proposed use is lawful. Verify the source and seek qualified advice when the risk matters.',
          ],
        ),
        _LegalSection(
          title: '4. Be considerate of Wikimedia and map services',
          paragraphs: const [
            'CommonsLens limits concurrent requests, spaces requests, caches some pipeline results, and backs off when Wikimedia asks it to slow down. Even so, each search ultimately uses shared community infrastructure.',
            'Please avoid many continuous or repetitive queries, rapid refreshes, several query-heavy tabs at once, or repeatedly running large pipelines without a pause. A short pause between large batches is polite and helps keep Wikimedia responsive for everyone.',
          ],
          bullets: const [
            'Do not bypass rate limits, retry signals, technical safeguards, or provider usage policies.',
            'Do not use the interactive site as a bot, scraper, crawler, or high-volume automation endpoint.',
            'Do not bulk-fetch or prefetch map tiles for offline use.',
            'For sustained automated research, use the official APIs directly and follow their identification, throttling, robot, and licensing rules.',
          ],
          links: const [
            _PolicyLink('Wikimedia API usage guidelines', _wikimediaApiUrl),
          ],
        ),
        const _LegalSection(
          title: '5. Acceptable use',
          paragraphs: [
            'Use CommonsLens only lawfully and in a way that does not damage, overload, disable, disrupt, probe, or interfere with CommonsLens or any connected service. Do not use it to infringe rights, distribute unlawful material, misrepresent authorship, evade access controls, introduce malicious code, or attempt unauthorized access.',
            'You are responsible for your searches, downloads, exports, publications, and downstream use of any media or metadata.',
          ],
        ),
        const _LegalSection(
          title: '6. Third-party services and links',
          paragraphs: [
            'CommonsLens connects to Wikimedia Commons, Wikidata, Wikimedia-hosted media, OpenStreetMap and Esri map tiles, GitHub Pages, and external source or licence pages. Their own terms, privacy policies, licences, availability rules, and usage policies apply when your browser contacts them. CommonsLens cannot control their content or practices.',
          ],
        ),
        const _LegalSection(
          title: '7. Availability, accuracy, and warranties',
          paragraphs: [
            'CommonsLens is provided free of charge on an “as is” and “as available” basis. Search results, metadata, rights fields, translations, generated snippets, map positions, exports, and third-party APIs may be incomplete, inaccurate, delayed, changed, or unavailable. Features can change or stop without notice.',
            'To the extent permitted by law, no warranty is made about accuracy, fitness for a particular purpose, non-infringement, uninterrupted availability, or preservation of locally saved data. Keep your own copy of anything important.',
          ],
        ),
        const _LegalSection(
          title: '8. Limitation of responsibility',
          paragraphs: [
            'To the extent permitted by applicable law, CommonsLens and its maintainers are not liable for losses arising from your use of the service, reliance on metadata or licence summaries, third-party content or services, unavailable or corrupted data, or your reuse of a file. Nothing here excludes a right or liability that the law does not allow to be excluded.',
          ],
        ),
        const _LegalSection(
          title: '9. Source code, changes, and questions',
          paragraphs: [
            'The CommonsLens software source code is open source under the Apache License 2.0, except for third-party material identified under its own licence notices. The Apache licence permits use, modification, and distribution subject to its conditions. It does not change or replace the separate licences and rights attached to Wikimedia media or data displayed through CommonsLens.',
            'These Terms may be updated as CommonsLens changes. The effective date below identifies this version. Questions or corrections can be raised in the public GitHub repository; do not post private or sensitive information in a public issue.',
          ],
          links: [
            _PolicyLink('CommonsLens source code', _sourceUrl),
            _PolicyLink('Apache License 2.0', _apacheLicenseUrl),
          ],
        ),
      ],
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalPageScaffold(
      eyebrow: 'PRIVACY POLICY',
      title: 'What CommonsLens collects—and what it does not',
      summary:
          'CommonsLens has no analytics, advertising trackers, accounts, or private application database. Most work happens in your browser. Only the outside services needed to deliver hosting, Wikimedia content, and map tiles receive ordinary web requests.',
      sections: [
        const _LegalSection(
          title: 'The short version',
          bullets: [
            'You do not give CommonsLens a name, email address, password, payment method, or profile.',
            'CommonsLens does not use visitor analytics, advertising, fingerprinting, session-recording, or behavioural-tracking services.',
            'Searches go from your browser to Wikimedia services; map views request tiles from OpenStreetMap or Esri.',
            'Saved pipelines, notes, query caches, and your image-preview preference stay in storage in your browser.',
            'CommonsLens does not sell personal information, run ads, create user profiles, or transmit interaction events to an analytics provider.',
          ],
        ),
        const _LegalSection(
          title: '1. No analytics or behavioural tracking',
          paragraphs: [
            'CommonsLens does not load visitor analytics, tag managers, advertising pixels, telemetry SDKs, session replay tools, or behavioural-tracking services. The application does not send page views, searches, filters, file titles, downloads, clicks, map activity, device identifiers, or interaction events to CommonsLens or an analytics provider.',
            'A static Google Search Console ownership-verification file is published with the site. It contains no script, cookie, pixel, or executable code, and it is not loaded by ordinary pages. Google may request that file periodically to confirm site ownership; it does not track visitors.',
            'CommonsLens does not intentionally set tracking cookies. Browser storage used for application preferences, saved pipelines, and caches is described below and is not used to follow you across sites.',
          ],
        ),
        const _LegalSection(
          title: '2. Information kept only on your device',
          bullets: [
            'Local storage: whether the asset viewer should preview web-optimised or full-resolution images.',
            'IndexedDB: saved visual pipeline graphs, node settings, positions, names and notes, plus cached Wikimedia query results and their public file metadata.',
            'Browser and service-worker caches: application files, images, media, and map/API responses as managed by your browser and the providers’ cache rules.',
            'Downloads and exports: files, ZIP archives, CSV/JSON data, and exported pipeline definitions go to the location you choose on your device.',
          ],
          paragraphs: [
            'This local data is not synced to a CommonsLens account or uploaded to a CommonsLens server. Pipeline query results are treated as fresh for one hour, but a local record can remain until it is overwritten, cleared inside the pipeline tools, evicted by the browser, or removed when you clear site data. Saved graphs remain until you delete them or clear site data.',
          ],
        ),
        _LegalSection(
          title: '3. Requests made to other services',
          paragraphs: const [
            'CommonsLens is a browser client, so your browser contacts providers directly. Those providers normally receive the IP address, user agent, requested URL/resource, time, referrer where supplied, and other standard request information. They handle that information under their own policies.',
          ],
          bullets: const [
            'GitHub Pages hosts and delivers the application and may log page requests and technical usage data.',
            'Wikimedia Commons and Wikidata receive search terms, filters, file/page names, and API requests. Wikimedia media hosts receive thumbnail and original-file requests.',
            'OpenStreetMap receives requests for visible multilingual street-map tiles when that layer is used.',
            'Esri receives requests for visible English street-map, satellite-imagery, and reference tiles when those layers are used.',
            'Opening a source, licence, global-usage, or repository link takes you to that external site, which then applies its own policy.',
          ],
          links: const [
            _PolicyLink('Wikimedia Privacy Policy', _wikimediaPrivacyUrl),
            _PolicyLink('GitHub Privacy Statement', _githubPrivacyUrl),
            _PolicyLink(
                'OpenStreetMap Foundation Privacy Policy', _osmPrivacyUrl),
            _PolicyLink('Esri Privacy Statement', _esriPrivacyUrl),
          ],
        ),
        const _LegalSection(
          title: '4. What CommonsLens does not collect',
          paragraphs: [
            'CommonsLens itself does not ask for or maintain the following:',
          ],
          bullets: [
            'Accounts, names, email addresses, phone numbers, postal addresses, passwords, identity documents, or profile details.',
            'Payment or financial information.',
            'Your contacts, messages, camera, microphone, uploaded private files, or clipboard contents. The attribution tool only writes text you request to your clipboard.',
            'Your device’s precise live location. Map searches use coordinates or places you choose; displayed file coordinates are public media metadata.',
            'Page-view or interaction analytics, a CommonsLens-owned server log, cloud database, advertising profile, data-broker feed, or cross-device identity.',
          ],
        ),
        const _LegalSection(
          title: '5. Why this design is more private',
          paragraphs: [
            'No account means there is no CommonsLens identity profile to leak, sell, or connect to your searches. Local pipelines and exports avoid sending your research workflow to an application backend. Direct, visible provider requests make the service boundaries inspectable, and the full source code lets anyone verify the implementation.',
            'This does not make web use invisible: hosting, Wikimedia, map providers, and external sites still receive the requests described above. The privacy advantage is the absence of behavioural analytics plus data minimisation and local processing—not a claim of total anonymity.',
          ],
        ),
        const _LegalSection(
          title: '6. Your choices and data deletion',
          bullets: [
            'Clear CommonsLens site data in your browser to remove local preferences, caches, and saved pipelines.',
            'Use the pipeline Clear Cache control to remove cached results while keeping saved graphs.',
            'Avoid the map or a particular layer if you do not want requests sent to its tile provider.',
            'Avoid entering personal, confidential, or sensitive material into searches, URLs, pipeline labels, or notes.',
          ],
        ),
        const _LegalSection(
          title: '7. Children, security, and international processing',
          paragraphs: [
            'CommonsLens is a general research tool and is not designed to collect information from children. Because there are no accounts or direct submissions, CommonsLens does not knowingly maintain a child’s profile. If a minor uses the site, a parent or guardian should help them avoid entering personal information in searches.',
            'The site uses HTTPS, but no internet transmission or browser storage is perfectly secure. Providers may process requests in countries other than your own under their policies and applicable law.',
          ],
        ),
        const _LegalSection(
          title: '8. Changes and contact',
          paragraphs: [
            'This policy will be updated when collection or providers materially change. The effective date below identifies the current version.',
            'For a privacy question or correction concerning CommonsLens, open an issue in the public source repository. Do not include sensitive information in a public issue. Requests about data controlled by GitHub, Wikimedia, OpenStreetMap, or Esri should be made directly to that provider.',
          ],
          links: [
            _PolicyLink('CommonsLens source code and issue tracker', _sourceUrl)
          ],
        ),
      ],
    );
  }
}

class _LegalPageScaffold extends StatelessWidget {
  const _LegalPageScaffold({
    required this.eyebrow,
    required this.title,
    required this.summary,
    required this.sections,
  });

  final String eyebrow;
  final String title;
  final String summary;
  final List<_LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back to search',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
        ),
        title: Text(
          'COMMONSLENS  ·  $eyebrow',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 42, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: const TextStyle(
                      color: Color(0xFF7AABFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    summary,
                    style: const TextStyle(
                      color: Color(0xFFC3C3C3),
                      fontSize: 17,
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Effective and last reviewed: 22 October 2026',
                    style: TextStyle(
                      color: Color(0xFF727272),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 38),
                  ...sections,
                  const SizedBox(height: 28),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({
    required this.title,
    this.paragraphs = const [],
    this.bullets = const [],
    this.links = const [],
  });

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
  final List<_PolicyLink> links;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...paragraphs.map(
            (paragraph) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                paragraph,
                style: const TextStyle(
                  color: Color(0xFFADADAD),
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
            ),
          ),
          ...bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: Color(0xFF3D7EFF),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      bullet,
                      style: const TextStyle(
                        color: Color(0xFFADADAD),
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (links.isNotEmpty) const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: links
                .map(
                  (link) => OutlinedButton.icon(
                    onPressed: () => _openExternal(link.url),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: Text(link.label),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9AB9FF),
                      side: const BorderSide(color: Color(0xFF303C54)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _PolicyLink {
  const _PolicyLink(this.label, this.url);

  final String label;
  final String url;
}
