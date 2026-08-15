import SwiftUI

// Admin Social tab: run a render batch, then watch the queue drain.
//
// Instagram publishes itself (publish-social-post cron), so nothing here
// gates a post — the list is a monitor with a kill switch. TikTok's Content
// Posting API keeps unaudited clients' posts self-visible only, so until that
// audit clears its cards go out by hand via the share action on each row.

struct SocialExportView: View {
    @ObservedObject var store: SocialExportStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                platformPicker
                batchControls
                if let error = store.lastError {
                    banner(error, tone: .danger)
                }
                if let summary = store.lastRunSummary {
                    banner(summary, tone: .neutral)
                }
                queueSection
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(PassportTheme.background)
        .refreshable { await store.loadQueue() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Social")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(PassportTheme.textPrimary)
            Text("Render job carousels to 1080×1350 cards and queue them for posting.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PassportTheme.textSecondary)
        }
    }

    private var platformPicker: some View {
        Picker("Platform", selection: $store.platform) {
            ForEach(SocialPlatform.allCases) { platform in
                Text(platform.title).tag(platform)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: store.platform) { _, _ in
            Task { await store.loadQueue() }
        }
    }

    // MARK: - Batch

    private var batchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await store.runBatch() }
            } label: {
                HStack(spacing: 10) {
                    if store.isRunning {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "square.stack.3d.up.fill")
                    }
                    Text(store.isRunning ? "Rendering…" : "Render \(SocialExportStore.defaultBatchSize) cards")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(PassportTheme.accent)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(store.isRunning)

            if let progress = store.progress {
                Text(progress)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PassportTheme.textMuted)
                    .lineLimit(1)
            }

            if store.platform == .tiktok {
                Text("TikTok posts go out by hand until the Content Posting API audit clears — use the share button on each card.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PassportTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private enum BannerTone { case danger, neutral }

    private func banner(_ text: String, tone: BannerTone) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tone == .danger ? PassportTheme.danger : PassportTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(PassportTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Queue

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Queue")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary)
                Spacer()
                Text("\(store.queue.count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PassportTheme.textMuted)
            }

            if store.queue.isEmpty {
                Text("Nothing queued yet. Render a batch to fill it.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PassportTheme.textMuted)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(store.queue) { post in
                    SocialPostRow(post: post, store: store)
                }
            }
        }
    }
}

// MARK: - Row

private struct SocialPostRow: View {
    let post: SocialPostRecord
    @ObservedObject var store: SocialExportStore

    private var firstImageURL: URL? {
        post.imagePaths.first.flatMap { store.publicURL(for: $0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    statusChip
                    Text("\(post.imagePaths.count) slides")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PassportTheme.textMuted)
                }

                Text(post.caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PassportTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = post.error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PassportTheme.danger)
                        .lineLimit(2)
                }

                actions
            }
        }
        .padding(12)
        .background(PassportTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var thumbnail: some View {
        AsyncImage(url: firstImageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(PassportTheme.border.opacity(0.4))
            }
        }
        .frame(width: 64, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusChip: some View {
        Text(post.status.rawValue.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(chipColor.opacity(0.18))
            .foregroundStyle(chipColor)
            .clipShape(Capsule())
    }

    private var chipColor: Color {
        switch post.status {
        case .rendered: return PassportTheme.accentSoft
        case .posted:   return Color(red: 0.18, green: 0.55, blue: 0.34)
        case .failed:   return PassportTheme.danger
        case .skipped:  return PassportTheme.textMuted
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 14) {
            if let url = post.permalink.flatMap(URL.init(string:)) {
                Link(destination: url) {
                    Label("View post", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .bold))
                }
            }

            // Hand-off for TikTok (and any manual repost): the images plus the
            // caption, straight into the share sheet.
            if post.status != .posted, let url = firstImageURL {
                ShareLink(item: url, message: Text(post.caption)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .bold))
                }
            }

            if post.status == .rendered {
                Button {
                    Task { await store.setStatus(post, to: .skipped) }
                } label: {
                    Label("Skip", systemImage: "xmark.circle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PassportTheme.danger)
                }
            } else if post.status == .skipped {
                Button {
                    Task { await store.setStatus(post, to: .rendered) }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .bold))
                }
            }
        }
        .padding(.top, 2)
    }
}
