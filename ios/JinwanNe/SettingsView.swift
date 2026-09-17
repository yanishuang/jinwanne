import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showJoinConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var aliasDraft = ""
    @State private var aliasSaved = false
    @FocusState private var aliasFocused: Bool

    var body: some View {
        List {
            Section {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label(L10n.text("我的小本本", "My little diary"), systemImage: "book.closed")
                }
            }

            Section {
                TextField(L10n.text("输入用户名", "Enter a username"), text: $aliasDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($aliasFocused)
                    .disabled(!model.canSave)
                    .submitLabel(.done)
                    .onSubmit(saveAlias)
                    .onChange(of: aliasDraft) { _, value in
                        if value.count > 16 { aliasDraft = String(value.prefix(16)) }
                        aliasSaved = false
                    }

                HStack {
                    Button(L10n.text("保存用户名", "Save username"), action: saveAlias)
                        .foregroundStyle(AppPalette.blue)
                        .disabled(!model.canSave || aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    if aliasSaved {
                        Label(L10n.text("已保存", "Saved"), systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(AppPalette.blue)
                    }
                }

                Button(L10n.text("换一个随机用户名", "Give me a random username")) {
                    aliasFocused = false
                    Task {
                        if await model.updateAlias("") {
                            aliasDraft = model.session?.profile.alias ?? ""
                            aliasSaved = true
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(AppPalette.muted)
                .disabled(!model.canSave)
            } header: {
                Text(L10n.text("用户名", "Username"))
            } footer: {
                Text(L10n.text("用户名会显示在排行榜。使用 2–16 个中文、字母或数字，也可以包含空格、_、-、·；不能与其他用户重复。", "Your username appears if you join the board. Use 2–16 letters, numbers, or Chinese characters. Spaces, _, -, and · are allowed. Usernames must be unique."))
            }

            Section(L10n.text("匿名排行 · 自愿公开", "Leaderboard · Your choice")) {
                if let profile = model.session?.profile {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(profile.alias).font(.subheadline.weight(.medium))
                        Text(L10n.text("只公开用户名、成功和失败天数，不公开具体日期与备注。", "Only your username and day totals are public. Specific dates and notes stay off the board."))
                            .font(.caption)
                            .foregroundStyle(AppPalette.muted)
                    }
                    if profile.participating {
                        Button(L10n.text("退出排行榜", "Leave the leaderboard"), role: .destructive) {
                            Task { _ = await model.updateProfile(participating: false) }
                        }
                        .disabled(!model.canSave)
                    } else {
                        Button(L10n.text("开启匿名排行", "Join the leaderboard")) { showJoinConfirmation = true }
                            .foregroundStyle(AppPalette.blue)
                            .disabled(!model.canSave)
                    }
                }
            }

            Section(L10n.text("隐私与数据", "Privacy & data")) {
                Text(L10n.text("记录通过当前设备的匿名身份访问。删除 App 或清除数据后无法找回；本版不支持跨设备登录。", "Your entries are accessed through an anonymous identity on this device. Deleting the app or clearing its data can permanently lose access. Signing in on another device is not supported."))
                Text(L10n.text("服务器管理员可以访问数据库。App 不会向伴侣发送申请或通知。失败表示申请被拒绝，亲密始终以双方自愿为前提。", "Server administrators can access the database. The app never sends requests or notifications to your partner. “Not tonight” records a declined invitation. Intimacy always requires mutual consent."))
            }
            .font(.caption)
            .foregroundStyle(AppPalette.muted)

            Section(L10n.text("关于", "About")) {
                Link(L10n.text("隐私政策", "Privacy policy"), destination: L10n.privacyURL)
                Link(L10n.text("用户支持", "Support"), destination: L10n.supportURL)
                if L10n.isChinese {
                    Link("浙ICP备2026018883号-4A", destination: URL(string: "https://beian.miit.gov.cn/")!)
                }
            }

            Section {
                Button(L10n.text("删除全部数据", "Delete all my data"), role: .destructive) { showDeleteConfirmation = true }
                    .disabled(!model.canSave)
            } footer: {
                Text(L10n.text("删除当前匿名身份、全部记录和排名信息，无法撤销。", "Permanently deletes your anonymous identity, all entries, and leaderboard data. This cannot be undone."))
            }
        }
        .navigationTitle(L10n.text("设置", "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if aliasDraft.isEmpty { aliasDraft = model.session?.profile.alias ?? "" }
        }
        .onChange(of: model.session?.profile.alias) { _, alias in
            guard let alias, !aliasFocused else { return }
            aliasDraft = alias
        }
        .confirmationDialog(L10n.text("开启匿名排行？", "Join the leaderboard?"), isPresented: $showJoinConfirmation, titleVisibility: .visible) {
            Button(L10n.text("同意并开启", "Agree and join")) { Task { _ = await model.updateProfile(participating: true) } }
                .disabled(!model.canSave)
            Button(L10n.text("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("排行榜会公开你的用户名以及成功、失败天数，不公开日期和备注。请勿使用真实姓名或联系方式，可随时退出。", "Your username and totals for yes nights and rain checks will be public. Dates and notes stay off the board. Don’t use your real name or contact details. You can leave anytime."))
        }
        .alert(L10n.text("永久删除全部数据？", "Permanently delete all data?"), isPresented: $showDeleteConfirmation) {
            Button(L10n.text("永久删除", "Delete permanently"), role: .destructive) { Task { _ = await model.eraseAccount() } }
                .disabled(!model.canSave)
            Button(L10n.text("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("此操作无法撤销。", "This cannot be undone."))
        }
    }

    private func saveAlias() {
        let alias = aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return }
        aliasFocused = false
        Task {
            if await model.updateAlias(alias) {
                aliasDraft = model.session?.profile.alias ?? alias
                aliasSaved = true
            }
        }
    }
}
