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
                    Label("我的小本本", systemImage: "book.closed")
                }
            }

            Section {
                TextField("输入用户名", text: $aliasDraft)
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
                    Button("保存用户名", action: saveAlias)
                        .foregroundStyle(AppPalette.blue)
                        .disabled(!model.canSave || aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    if aliasSaved {
                        Label("已保存", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(AppPalette.blue)
                    }
                }

                Button("换一个随机用户名") {
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
                Text("用户名")
            } footer: {
                Text("用户名会显示在排行榜。使用 2–16 个中文、字母或数字，也可以包含空格、_、-、·；不能与其他用户重复。")
            }

            Section("匿名排行 · 自愿公开") {
                if let profile = model.session?.profile {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(profile.alias).font(.subheadline.weight(.medium))
                        Text("只公开用户名、成功和失败天数，不公开具体日期与备注。")
                            .font(.caption)
                            .foregroundStyle(AppPalette.muted)
                    }
                    if profile.participating {
                        Button("退出排行榜", role: .destructive) {
                            Task { _ = await model.updateProfile(participating: false) }
                        }
                        .disabled(!model.canSave)
                    } else {
                        Button("开启匿名排行") { showJoinConfirmation = true }
                            .foregroundStyle(AppPalette.blue)
                            .disabled(!model.canSave)
                    }
                }
            }

            Section("隐私与数据") {
                Text("记录通过当前设备的匿名身份访问。删除 App 或清除数据后无法找回；本版不支持跨设备登录。")
                Text("服务器管理员可以访问数据库。App 不会向伴侣发送申请或通知。失败表示申请被拒绝，亲密始终以双方自愿为前提。")
            }
            .font(.caption)
            .foregroundStyle(AppPalette.muted)

            Section("关于") {
                Link("隐私政策", destination: URL(string: "https://jinwanne.woaizhuzhu.com/privacy")!)
                Link("用户支持", destination: URL(string: "https://jinwanne.woaizhuzhu.com/support")!)
                Link("浙ICP备2026018883号-4A", destination: URL(string: "https://beian.miit.gov.cn/")!)
            }

            Section {
                Button("删除全部数据", role: .destructive) { showDeleteConfirmation = true }
                    .disabled(!model.canSave)
            } footer: {
                Text("删除当前匿名身份、全部记录和排名信息，无法撤销。")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if aliasDraft.isEmpty { aliasDraft = model.session?.profile.alias ?? "" }
        }
        .onChange(of: model.session?.profile.alias) { _, alias in
            guard let alias, !aliasFocused else { return }
            aliasDraft = alias
        }
        .confirmationDialog("开启匿名排行？", isPresented: $showJoinConfirmation, titleVisibility: .visible) {
            Button("同意并开启") { Task { _ = await model.updateProfile(participating: true) } }
                .disabled(!model.canSave)
            Button("取消", role: .cancel) {}
        } message: {
            Text("排行榜会公开你的用户名以及成功、失败天数，不公开日期和备注。请勿使用真实姓名或联系方式，可随时退出。")
        }
        .alert("永久删除全部数据？", isPresented: $showDeleteConfirmation) {
            Button("永久删除", role: .destructive) { Task { _ = await model.eraseAccount() } }
                .disabled(!model.canSave)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
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
