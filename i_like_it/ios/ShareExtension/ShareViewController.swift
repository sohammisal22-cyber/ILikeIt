import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

// MARK: - Models

struct CachedFolder: Codable {
    let id: Int
    let name: String
    let icon: String
}

// MARK: - UIColor Hex

extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard s.count == 6, let rgb = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >>  8) & 0xFF) / 255,
            blue:  CGFloat((rgb >>  0) & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Design Tokens (matching app_theme.dart dark palette)

private enum C {
    static let bg       = UIColor(hex: "#030804")!   // _darkBackground
    static let surface  = UIColor(hex: "#0A0B0B")!   // _darkSurface
    static let green    = UIColor(hex: "#26973C")!   // _darkPrimary
    static let text     = UIColor(hex: "#FFFFFF")!
    static let subtext  = UIColor(hex: "#8A9A8A")!
    static let border   = UIColor(hex: "#26973C")!.withAlphaComponent(0.22)
    static let inputBg  = UIColor(hex: "#111311")!
    static let iconBg   = UIColor(hex: "#26973C")!.withAlphaComponent(0.12)
    static let divider  = UIColor.white.withAlphaComponent(0.06)
}

// MARK: - ShareViewController

class ShareViewController: UIViewController {

    // MARK: - Constants
    private let appGroup        = "group.com.ilikeit.app"
    private let sharedKey       = "sharedText"
    private let foldersKey      = "cachedFolders"
    private let pendingLink     = "pendingSaveLink"
    private let pendingFolderId = "pendingSaveFolderId"
    private let pendingNewFolder = "pendingNewFolderName"
    private let customURLScheme = "ilikeit://share"

    // MARK: - State
    private var extractedURL: String = ""
    private var allFolders: [CachedFolder] = []
    private var filteredFolders: [CachedFolder] = []
    private var searchText: String = "" {
        didSet { applyFilter() }
    }

    // MARK: - UI
    private var cardView: UIView!
    private var dimView: UIView!
    private var tableView: UITableView!
    private var searchField: UITextField!
    private var cardBottomConstraint: NSLayoutConstraint!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupDim()
        extractSharedURL { [weak self] url in
            DispatchQueue.main.async {
                self?.extractedURL = url
                self?.loadFolders()
                self?.buildUI()
                self?.animateIn()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Dim

    private func setupDim() {
        dimView = UIView(frame: view.bounds)
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0)
        view.addSubview(dimView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(bgTapped))
        tap.delegate = self
        dimView.addGestureRecognizer(tap)
        UIView.animate(withDuration: 0.25) { self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.6) }
    }

    // MARK: - URL Extraction

    private func extractSharedURL(completion: @escaping (String) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion("")
            return
        }
        var providers: [NSItemProvider] = []
        for item in items {
            providers.append(contentsOf: item.attachments ?? [])
        }
        guard !providers.isEmpty else {
            completion("")
            return
        }

        let group = DispatchGroup()
        var foundURL: String? = nil

        let urlType = UTType.url.identifier
        let plainTextType = UTType.plainText.identifier
        let generalTextType = UTType.text.identifier

        for provider in providers {
            if foundURL != nil { break }

            if provider.hasItemConformingToTypeIdentifier(urlType) {
                group.enter()
                provider.loadItem(forTypeIdentifier: urlType, options: nil) { item, _ in
                    defer { group.leave() }
                    if let u = item as? URL {
                        foundURL = self.cleanURL(from: u.absoluteString)
                    } else if let u = item as? NSURL, let s = u.absoluteString {
                        foundURL = self.cleanURL(from: s)
                    } else if let s = item as? String {
                        foundURL = self.cleanURL(from: s)
                    }
                }
            }

            if provider.hasItemConformingToTypeIdentifier(plainTextType) || provider.hasItemConformingToTypeIdentifier(generalTextType) {
                let typeToUse = provider.hasItemConformingToTypeIdentifier(plainTextType) ? plainTextType : generalTextType
                group.enter()
                provider.loadItem(forTypeIdentifier: typeToUse, options: nil) { item, _ in
                    defer { group.leave() }
                    if let s = item as? String {
                        let cleaned = self.cleanURL(from: s)
                        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
                            foundURL = cleaned
                        } else if foundURL == nil {
                            foundURL = s
                        }
                    } else if let a = item as? NSAttributedString {
                        let cleaned = self.cleanURL(from: a.string)
                        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
                            foundURL = cleaned
                        } else if foundURL == nil {
                            foundURL = a.string
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            completion(foundURL ?? "")
        }
    }

    private func cleanURL(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(https?://[^\s]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
           let range = Range(match.range(at: 1), in: trimmed) {
            var extracted = String(trimmed[range])
            while extracted.hasSuffix(".") || extracted.hasSuffix(",") || extracted.hasSuffix("!") ||
                  extracted.hasSuffix("?") || extracted.hasSuffix(")") || extracted.hasSuffix("]") ||
                  extracted.hasSuffix(">") || extracted.hasSuffix("\"") || extracted.hasSuffix("'") {
                extracted.removeLast()
            }
            return extracted
        }
        return trimmed
    }


    // MARK: - Folders

    private func loadFolders() {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let json = defaults.string(forKey: foldersKey),
              let data = json.data(using: .utf8) else { return }
        allFolders = (try? JSONDecoder().decode([CachedFolder].self, from: data)) ?? []
        filteredFolders = allFolders
    }

    private func applyFilter() {
        if searchText.isEmpty {
            filteredFolders = allFolders
        } else {
            filteredFolders = allFolders.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        tableView?.reloadData()
    }

    // MARK: - UI Build

    private func buildUI() {
        // Card
        cardView = UIView()
        cardView.backgroundColor = C.bg
        cardView.layer.cornerRadius = 20
        cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.5
        cardView.layer.shadowRadius = 24
        cardView.layer.shadowOffset = CGSize(width: 0, height: -6)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        // Card height = 80% of screen
        let cardHeight = view.bounds.height * 0.82

        cardBottomConstraint = cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: cardHeight)
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardBottomConstraint,
            cardView.heightAnchor.constraint(equalToConstant: cardHeight),
        ])
        view.layoutIfNeeded()

        buildInnerUI()

        // Keyboard avoidance
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func buildInnerUI() {
        // Drag handle
        let handle = UIView()
        handle.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        handle.layer.cornerRadius = 2.5
        handle.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(handle)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Select or Create Folder"
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = C.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        // Search container
        let searchContainer = UIView()
        searchContainer.backgroundColor = C.inputBg
        searchContainer.layer.cornerRadius = 14
        searchContainer.layer.borderWidth = 1
        searchContainer.layer.borderColor = C.border.cgColor
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(searchContainer)

        let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        searchIcon.tintColor = C.subtext
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        searchField = UITextField()
        searchField.placeholder = "Search folders..."
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search folders...",
            attributes: [.foregroundColor: C.subtext]
        )
        searchField.textColor = C.text
        searchField.font = UIFont.systemFont(ofSize: 15)
        searchField.backgroundColor = .clear
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.returnKeyType = .search
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        searchContainer.addSubview(searchIcon)
        searchContainer.addSubview(searchField)

        // Section label
        let sectionLabel = UILabel()
        sectionLabel.text = "Other folders:"
        sectionLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        sectionLabel.textColor = C.subtext
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(sectionLabel)

        // Table
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(FolderRow.self, forCellReuseIdentifier: FolderRow.id)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 58
        tableView.showsVerticalScrollIndicator = false
        tableView.keyboardDismissMode = .onDrag
        tableView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(tableView)

        // Bottom bar
        let bottomBar = buildBottomBar()
        cardView.addSubview(bottomBar)

        // Layout
        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            handle.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 4),

            titleLabel.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),

            searchContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            searchContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            searchContainer.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            searchContainer.heightAnchor.constraint(equalToConstant: 48),

            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 12),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 17),
            searchIcon.heightAnchor.constraint(equalToConstant: 17),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

            sectionLabel.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 16),
            sectionLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),

            tableView.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: cardView.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    private func buildBottomBar() -> UIView {
        let bar = UIView()
        bar.backgroundColor = C.bg
        bar.translatesAutoresizingMaskIntoConstraints = false

        // Top border
        let border = UIView()
        border.backgroundColor = C.divider
        border.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(border)

        // Cancel
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Cancel", for: .normal)
        cancelBtn.setTitleColor(C.green, for: .normal)
        cancelBtn.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        // Create new folder button
        let createBtn = UIButton(type: .system)
        createBtn.backgroundColor = .clear
        createBtn.layer.cornerRadius = 12
        createBtn.layer.borderWidth = 1.5
        createBtn.layer.borderColor = C.green.cgColor
        createBtn.translatesAutoresizingMaskIntoConstraints = false
        createBtn.addTarget(self, action: #selector(createFolderTapped), for: .touchUpInside)

        // Button content: icon + two lines
        let plusImg = UIImage(systemName: "plus.circle")?
            .withRenderingMode(.alwaysTemplate)
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        let iconView = UIImageView(image: plusImg)
        iconView.tintColor = C.green
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let createLabel = UILabel()
        createLabel.text = "Create new folder"
        createLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        createLabel.textColor = C.green

        let subLabel = UILabel()
        subLabel.text = "Tap to name it"
        subLabel.font = UIFont.systemFont(ofSize: 11)
        subLabel.textColor = C.green.withAlphaComponent(0.65)

        let textStack = UIStackView(arrangedSubviews: [createLabel, subLabel])
        textStack.axis = .vertical
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let btnStack = UIStackView(arrangedSubviews: [iconView, textStack])
        btnStack.axis = .horizontal
        btnStack.spacing = 7
        btnStack.alignment = .center
        btnStack.isUserInteractionEnabled = false
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        createBtn.addSubview(btnStack)

        bar.addSubview(cancelBtn)
        bar.addSubview(createBtn)

        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: bar.topAnchor),
            border.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5),

            cancelBtn.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            cancelBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            createBtn.leadingAnchor.constraint(equalTo: cancelBtn.trailingAnchor, constant: 12),
            createBtn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            createBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            createBtn.heightAnchor.constraint(equalToConstant: 48),

            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            btnStack.centerXAnchor.constraint(equalTo: createBtn.centerXAnchor),
            btnStack.centerYAnchor.constraint(equalTo: createBtn.centerYAnchor),
        ])

        return bar
    }

    // MARK: - Animation

    private func animateIn() {
        cardBottomConstraint.constant = 0
        UIView.animate(withDuration: 0.40, delay: 0,
                       usingSpringWithDamping: 0.84, initialSpringVelocity: 0.3,
                       options: .curveEaseOut) {
            self.view.layoutIfNeeded()
        }
    }

    private func animateOut(then done: @escaping () -> Void) {
        searchField?.resignFirstResponder()
        let h = view.bounds.height * 0.82
        cardBottomConstraint.constant = h
        UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseIn, animations: {
            self.view.layoutIfNeeded()
            self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0)
        }, completion: { _ in done() })
    }

    // MARK: - Keyboard

    @objc private func keyboardWillShow(_ n: Notification) {
        guard let info = n.userInfo,
              let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let dur = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        cardBottomConstraint.constant = -frame.height
        UIView.animate(withDuration: dur) { self.view.layoutIfNeeded() }
    }

    @objc private func keyboardWillHide(_ n: Notification) {
        guard let dur = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        cardBottomConstraint.constant = 0
        UIView.animate(withDuration: dur) { self.view.layoutIfNeeded() }
    }

    // MARK: - Actions

    @objc private func bgTapped() {
        animateOut { self.extensionContext?.completeRequest(returningItems: []) }
    }

    @objc private func cancelTapped() {
        animateOut { self.extensionContext?.completeRequest(returningItems: []) }
    }

    @objc private func searchChanged() {
        searchText = searchField.text ?? ""
    }

    @objc private func createFolderTapped() {
        searchField.resignFirstResponder()
        let alert = UIAlertController(title: "New Folder", message: "Enter a name for your new folder", preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.addTextField { tf in
            tf.placeholder = "Folder name"
            tf.autocapitalizationType = .sentences
            tf.textColor = .white
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create & Save", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            self.saveWithNewFolder(name: name)
        })
        present(alert, animated: true)
    }

    // MARK: - Save

    private func saveToFolder(_ folder: CachedFolder) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(extractedURL, forKey: sharedKey)
        defaults.set(extractedURL, forKey: pendingLink)
        defaults.set(String(folder.id), forKey: pendingFolderId)
        defaults.synchronize()
        tryOpenMainApp()
        showSuccess(folderName: folder.name, isNew: false)
    }

    private func saveWithNewFolder(name: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(extractedURL, forKey: sharedKey)
        defaults.set(extractedURL, forKey: pendingLink)
        defaults.set("new:\(name)", forKey: pendingFolderId)   // "new:FolderName" signals main app to create it
        defaults.set(name, forKey: pendingNewFolder)
        defaults.synchronize()
        tryOpenMainApp()
        showSuccess(folderName: name, isNew: true)
    }

    private func tryOpenMainApp() {
        guard let url = URL(string: customURLScheme) else { return }
        extensionContext?.open(url, completionHandler: nil)
        var r: UIResponder? = self
        let s = sel_registerName("openURL:")
        while let rr = r { if rr.responds(to: s) { _ = rr.perform(s, with: url); break }; r = rr.next }
    }

    // MARK: - Success

    private func showSuccess(folderName: String, isNew: Bool) {
        searchField.resignFirstResponder()

        // Fade out current content
        cardView.subviews.forEach { v in
            UIView.animate(withDuration: 0.15) { v.alpha = 0 }
        }

        // Shrink card
        cardBottomConstraint.constant = 0
        let smallHeight = view.bounds.height * 0.82
        cardView.constraints.first { $0.firstAttribute == .height }?.constant = 220
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.view.layoutIfNeeded()
        }

        // Success view
        let sv = UIView()
        sv.alpha = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(sv)

        // Circle
        let circle = UIView()
        circle.backgroundColor = C.green
        circle.layer.cornerRadius = 34
        circle.translatesAutoresizingMaskIntoConstraints = false

        let check = UIImageView(image: UIImage(systemName: "checkmark")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)))
        check.tintColor = .white
        check.contentMode = .scaleAspectFit
        check.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(check)

        let savedLbl = UILabel()
        savedLbl.text = "Link Saved!"
        savedLbl.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        savedLbl.textColor = C.text

        let folderLbl = UILabel()
        folderLbl.text = isNew ? "New folder \"\(folderName)\" will be created" : "Saved to \"\(folderName)\""
        folderLbl.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        folderLbl.textColor = C.subtext
        folderLbl.textAlignment = .center
        folderLbl.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [circle, savedLbl, folderLbl])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(stack)

        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 68),
            circle.heightAnchor.constraint(equalToConstant: 68),
            check.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 26),
            check.heightAnchor.constraint(equalToConstant: 26),

            stack.centerXAnchor.constraint(equalTo: sv.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: sv.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: sv.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: sv.trailingAnchor, constant: -24),

            sv.topAnchor.constraint(equalTo: cardView.topAnchor),
            sv.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])

        circle.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        UIView.animate(withDuration: 0.12, delay: 0.15) { sv.alpha = 1 }
        UIView.animate(withDuration: 0.5, delay: 0.15,
                       usingSpringWithDamping: 0.55, initialSpringVelocity: 0.6) {
            circle.transform = .identity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.animateOut { self?.extensionContext?.completeRequest(returningItems: []) }
        }
    }
}

// MARK: - UITableViewDataSource & Delegate

extension ShareViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredFolders.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FolderRow.id, for: indexPath) as! FolderRow
        cell.configure(with: filteredFolders[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        saveToFolder(filteredFolders[indexPath.row])
    }
}

// MARK: - UITextFieldDelegate

extension ShareViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder(); return true
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ShareViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return touch.view == dimView
    }
}

// MARK: - FolderRow

class FolderRow: UITableViewCell {
    static let id = "FolderRow"

    private let folderIcon = UIImageView()
    private let nameLabel  = UILabel()
    private let divider    = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        folderIcon.image = UIImage(systemName: "folder")?
            .withRenderingMode(.alwaysTemplate)
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .light))
        folderIcon.tintColor = UIColor(hex: "#26973C")!
        folderIcon.contentMode = .scaleAspectFit
        folderIcon.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        divider.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        divider.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(folderIcon)
        contentView.addSubview(nameLabel)
        contentView.addSubview(divider)

        NSLayoutConstraint.activate([
            folderIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            folderIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            folderIcon.widthAnchor.constraint(equalToConstant: 24),
            folderIcon.heightAnchor.constraint(equalToConstant: 22),

            nameLabel.leadingAnchor.constraint(equalTo: folderIcon.trailingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            divider.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with folder: CachedFolder) {
        nameLabel.text = folder.name
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        UIView.animate(withDuration: 0.1) {
            self.contentView.backgroundColor = highlighted
                ? UIColor(hex: "#26973C")!.withAlphaComponent(0.10)
                : .clear
        }
    }
}
