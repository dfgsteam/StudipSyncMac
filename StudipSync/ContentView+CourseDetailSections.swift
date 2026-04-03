import SwiftUI

extension ContentView {
    @ViewBuilder
    func courseDetailCard(for course: CourseDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(course.title)
                        .font(.title3.weight(.semibold))
                    if let subtitle = nonEmpty(course.subtitle) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let summary = courseMetaSummary(for: course) {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(courseOverviewHeaderLabel(for: course))
                    .font(.headline)
            }

            if shouldShowNewsBlock(for: course.id) {
                newsDemoBlock(for: course)
            }

            HStack(spacing: 10) {
                courseSectionNavigation(for: course)

                Button {
                    Task {
                        await forceReloadAllDetailContent(for: course.id)
                    }
                } label: {
                    if prefetchingCourseIDs.contains(course.id) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Alle neu laden", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(prefetchingCourseIDs.contains(course.id))
            }

            HStack(spacing: 10) {
                if supportsDetailSearch(for: selectedCourseDetailSectionID) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(
                            "In \(sectionTitle(for: selectedCourseDetailSectionID)) filtern",
                            text: detailSearchBinding(for: selectedCourseDetailSectionID)
                        )
                        .textFieldStyle(.plain)

                        if !rawDetailSearchQuery(for: selectedCourseDetailSectionID).isEmpty {
                            Button {
                                detailSearchTextBySectionID[selectedCourseDetailSectionID] = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Filter leeren")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer(minLength: 8)

                if let loadedAtText = detailSectionLoadedAtText(courseID: course.id, sectionID: selectedCourseDetailSectionID) {
                    Text(loadedAtText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                ScrollView {
                    courseDetailSectionContent(for: course, sectionID: selectedCourseDetailSectionID)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } label: {
                Text(sectionTitle(for: selectedCourseDetailSectionID))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func courseOverviewHeaderLabel(for course: CourseDTO) -> String {
        if let number = nonEmpty(course.courseNumber) {
            return "Kursnr. \(number)"
        }
        return "Kursnr. -"
    }

    func courseRow(_ course: CourseDTO, isSelected: Bool) -> some View {
        Button {
            selectSidebarCourse(course.id)
            Task(priority: .utility) {
                await prefetchAllTabContentForCourse(course.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "book.closed")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(course.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    if let secondary = courseSecondaryLine(for: course) {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                        .padding(.leading, 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func courseSecondaryLine(for course: CourseDTO) -> String? {
        if let subtitle = nonEmpty(course.subtitle) { return subtitle }
        if let number = nonEmpty(course.courseNumber) { return "Kursnr. \(number)" }
        return courseTypeLabel(for: course)
    }

    func courseMetaSummary(for course: CourseDTO) -> String? {
        if let number = nonEmpty(course.courseNumber) {
            return "Kursnr. \(number)"
        }
        return nil
    }

    func courseTypeLabel(for course: CourseDTO) -> String? {
        if let type = course.courseType {
            return "Typ \(type)"
        }
        return nonEmpty(course.courseTypeID)
    }

    @ViewBuilder
    func courseDetailSectionContent(for course: CourseDTO, sectionID: String) -> some View {
        switch sectionID {
        case CourseDetailSection.description.id:
            if let description = nonEmpty(course.description) {
                Text(description)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                emptySectionText("Keine Beschreibung vorhanden.")
            }

        case CourseDetailSection.metadata.id:
            VStack(alignment: .leading, spacing: 8) {
                detailRow("Ort", nonEmpty(course.location))
                detailRow("Startsemester", nonEmpty(course.startSemesterRef))
                detailRow("Institut", nonEmpty(course.instituteID))
                detailRow("Sem-Klasse", nonEmpty(course.semClassID))
                detailRow("Sem-Typ", nonEmpty(course.semTypeID))
                detailRow("Zusatz", nonEmpty(course.miscellaneous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.files.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Dateien fuer diesen Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadFilesForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                filesBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.chat.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Chat/Threads fuer diesen Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadChatsForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                chatsBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.wiki.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Wiki-Seiten fuer diesen Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadWikisForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                wikisBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.participants.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Teilnehmer in diesem Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadParticipantsForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                participantsBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case CourseDetailSection.forum.id:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Forum-Kategorien fuer diesen Kurs:")
                    Spacer()
                    Button("Neu laden") {
                        Task { await forceReloadForumsForSelectedSection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                forumsBlock(for: course)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            emptySectionText("Dieser Bereich ist noch nicht belegt.")
        }
    }

    func newsDemoBlock(for course: CourseDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("News")
                    .font(.headline)
                Spacer()
                if let loadedAtText = detailSectionLoadedAtText(courseID: course.id, sectionID: "news") {
                    Text(loadedAtText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Neu laden") {
                    Task { await forceReloadNewsForSelectedCourse() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isLoadingCourseNews, courseNewsByCourseID[course.id] == nil {
                ProgressView("Lade Veranstaltungsnews ...")
                    .controlSize(.small)
            } else if let newsItems = courseNewsByCourseID[course.id], !newsItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(newsItems) { item in
                            newsRow(item, courseID: course.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    newsCommentsWindowBlock(for: course.id)
                }
            } else if let errorText = courseNewsErrorsByCourseID[course.id] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Keine Veranstaltungsnews vorhanden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func shouldShowNewsBlock(for courseID: String) -> Bool {
        if isLoadingCourseNews, courseNewsByCourseID[courseID] == nil {
            return true
        }
        if let errorText = courseNewsErrorsByCourseID[courseID], nonEmpty(errorText) != nil {
            return true
        }
        if let newsItems = courseNewsByCourseID[courseID] {
            return !newsItems.isEmpty
        }
        return false
    }

    func newsRow(_ newsItem: NewsDTO, courseID: String) -> some View {
        let isSelected = selectedNewsIDByCourseID[courseID] == newsItem.id

        return Button {
            selectedNewsIDByCourseID[courseID] = newsItem.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(nonEmpty(newsItem.title) ?? "News \(newsItem.id)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let content = nonEmpty(newsItem.content) {
                    let preview = content.contains("<") && content.contains(">")
                        ? plainText(fromHTML: content)
                        : content
                    if let preview = nonEmpty(preview) {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Text(newsMetadataLine(newsItem))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func newsCommentsWindowBlock(for courseID: String) -> some View {
        if let selectedNewsID = selectedNewsIDByCourseID[courseID] {
            if loadingNewsCommentIDs.contains(selectedNewsID), newsCommentsByNewsID[selectedNewsID] == nil {
                ProgressView("Lade Kommentare ...")
                    .controlSize(.small)
            } else if let comments = newsCommentsByNewsID[selectedNewsID], !comments.isEmpty {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(comments) { comment in
                        newsCommentRow(comment)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let errorText = newsCommentErrorsByNewsID[selectedNewsID] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine Kommentare zu dieser News.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Waehle eine News aus, um Kommentare zu sehen.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func newsCommentRow(_ comment: NewsCommentDTO) -> some View {
        let parsed = nonEmpty(comment.content).flatMap { content in
            if content.contains("<"), content.contains(">") {
                return nonEmpty(plainText(fromHTML: content) ?? content)
            }
            return nonEmpty(content)
        } ?? "(leer)"

        return VStack(alignment: .leading, spacing: 4) {
            Text(parsed)
                .font(.callout)
                .lineLimit(6)

            Text("Kommentar \(comment.id)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func courseSectionNavigation(for course: CourseDTO) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleCourseDetailSections) { section in
                    Button {
                        selectedCourseDetailSectionID = section.id
                    } label: {
                        HStack(spacing: 6) {
                            Label(section.title, systemImage: section.systemImage)
                                .font(.subheadline.weight(.medium))

                            if let count = sectionItemCount(for: section.id, courseID: course.id) {
                                Text("\(count)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedCourseDetailSectionID == section.id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                        .foregroundStyle(selectedCourseDetailSectionID == section.id ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    func sectionItemCount(for sectionID: String, courseID: String) -> Int? {
        switch sectionID {
        case CourseDetailSection.files.id:
            let contextKey = fileContextKey(courseID: courseID, folderID: nil)
            guard let files = filesByContextKey[contextKey], let folders = foldersByContextKey[contextKey] else {
                return nil
            }
            return files.count + folders.count
        case CourseDetailSection.chat.id:
            return chatsByCourseID[courseID]?.count
        case CourseDetailSection.wiki.id:
            return wikisByCourseID[courseID]?.count
        case CourseDetailSection.participants.id:
            return participantsByCourseID[courseID]?.count
        case CourseDetailSection.forum.id:
            return forumsByCourseID[courseID]?.count
        default:
            return nil
        }
    }

    func sectionTitle(for sectionID: String) -> String {
        visibleCourseDetailSections.first(where: { $0.id == sectionID })?.title
            ?? defaultCourseDetailSections.first(where: { $0.id == sectionID })?.title
            ?? "Bereich"
    }

    func supportsDetailSearch(for sectionID: String) -> Bool {
        switch sectionID {
        case CourseDetailSection.files.id,
             CourseDetailSection.chat.id,
             CourseDetailSection.wiki.id,
             CourseDetailSection.participants.id,
             CourseDetailSection.forum.id:
            return true
        default:
            return false
        }
    }

    func detailSearchBinding(for sectionID: String) -> Binding<String> {
        Binding(
            get: { detailSearchTextBySectionID[sectionID] ?? "" },
            set: { detailSearchTextBySectionID[sectionID] = $0 }
        )
    }

    func rawDetailSearchQuery(for sectionID: String) -> String {
        (detailSearchTextBySectionID[sectionID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedDetailSearchQuery(for sectionID: String) -> String {
        rawDetailSearchQuery(for: sectionID).lowercased()
    }

    func detailSearchNoResultsText(for sectionID: String) -> String {
        let raw = rawDetailSearchQuery(for: sectionID)
        guard !raw.isEmpty else { return "Keine Treffer gefunden." }
        return "Keine Treffer fuer \"\(raw)\"."
    }

    func detailSectionCacheKey(courseID: String, sectionID: String) -> String {
        "\(courseID)::\(sectionID)"
    }

    func markDetailSectionLoadedNow(courseID: String, sectionID: String) {
        detailSectionLoadedAtByKey[detailSectionCacheKey(courseID: courseID, sectionID: sectionID)] = Date()
    }

    func detailSectionLoadedAtText(courseID: String, sectionID: String) -> String? {
        guard let loadedAt = detailSectionLoadedAtByKey[detailSectionCacheKey(courseID: courseID, sectionID: sectionID)] else {
            return nil
        }
        return "Stand: \(Self.fileDateFormatter.string(from: loadedAt))"
    }

    func containsSearch(_ haystack: String, query: String) -> Bool {
        query.isEmpty || haystack.lowercased().contains(query)
    }

    func preloadWikiAvailability(for courseID: String) async {
        guard wikisByCourseID[courseID] == nil else { return }

        do {
            let pages = try await repository.fetchCourseWikiPages(courseID: courseID)
            if selectedCourseID == courseID {
                wikisByCourseID[courseID] = pages
                if pages.isEmpty, selectedCourseDetailSectionID == CourseDetailSection.wiki.id {
                    selectedCourseDetailSectionID = CourseDetailSection.description.id
                }
            }
        } catch {
            if selectedCourseID == courseID {
                wikiErrorsByCourseID[courseID] = "Fehler beim Laden der Wiki-Seiten: \(error.localizedDescription)"
            }
        }
    }

    func emptySectionText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func overviewMessageCard(_ message: String, isError: Bool) -> some View {
        let tint: Color = isError ? .red : .orange
        let icon = isError ? "exclamationmark.triangle.fill" : "info.circle.fill"

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .padding(.top, 1)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.1))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    func detailRow(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    func forumsBlock(for course: CourseDTO) -> some View {
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.forum.id)

        if isLoadingForums, forumsByCourseID[course.id] == nil {
            ProgressView("Lade Forum ...")
                .controlSize(.small)
        } else if let categories = forumsByCourseID[course.id], !categories.isEmpty {
            let filteredCategories = query.isEmpty ? categories : categories.filter { category in
                containsSearch(
                    [
                        nonEmpty(category.title),
                        forumMetadataLine(category),
                        category.id
                    ]
                    .compactMap { $0 }
                    .joined(separator: " "),
                    query: query
                )
            }

            if filteredCategories.isEmpty {
                Text(detailSearchNoResultsText(for: CourseDetailSection.forum.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Kategorien", systemImage: "rectangle.stack.bubble.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredCategories) { category in
                                forumCategoryRow(category, courseID: course.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                    let selectedID = selectedForumCategoryIDByCourseID[course.id]
                    if selectedID == nil || filteredCategories.contains(where: { $0.id == selectedID }) {
                        forumEntriesWindowBlock(for: course.id)
                    } else {
                        Text("Die aktuell ausgewaehlte Kategorie passt nicht zum Filter.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if let errorText = forumErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Forum-Kategorien gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func forumCategoryRow(_ category: StudIPResourceRepository.CourseForumCategory, courseID: String) -> some View {
        let isSelected = selectedForumCategoryIDByCourseID[courseID] == category.id

        return Button {
            selectedForumCategoryIDByCourseID[courseID] = category.id
            if selectedForumEntryIDByCategoryID[category.id] == nil {
                selectedForumEntryIDByCategoryID[category.id] = forumEntriesByCategoryID[category.id]?.first?.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.2))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: "text.bubble")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                        .padding(.top, 1)

                    Text(nonEmpty(category.title) ?? "Forum \(category.id)")
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    Spacer(minLength: 8)
                }

                Text(forumMetadataLine(category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func forumEntriesWindowBlock(for courseID: String) -> some View {
        if let selectedCategoryID = selectedForumCategoryIDByCourseID[courseID] {
            if loadingForumCategoryIDs.contains(selectedCategoryID), forumEntriesByCategoryID[selectedCategoryID] == nil {
                ProgressView("Lade Forum-Themen ...")
                    .controlSize(.small)
            } else if let entries = forumEntriesByCategoryID[selectedCategoryID], !entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Themen", systemImage: "text.bubble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(entries) { entry in
                                forumEntryRow(entry, categoryID: selectedCategoryID)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                    forumRepliesWindowBlock(categoryID: selectedCategoryID)
                }
            } else if let errorText = forumEntryErrorsByCategoryID[selectedCategoryID] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine Forum-Themen in dieser Kategorie.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Waehle eine Forum-Kategorie aus, um die Themen zu sehen.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func forumEntryRow(_ entry: ForumEntryDTO, categoryID: String) -> some View {
        let isSelected = selectedForumEntryIDByCategoryID[categoryID] == entry.id

        return Button {
            selectedForumEntryIDByCategoryID[categoryID] = entry.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(nonEmpty(entry.title) ?? "Eintrag \(entry.id)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let content = nonEmpty(entry.content) {
                    let preview = content.contains("<") && content.contains(">")
                        ? plainText(fromHTML: content)
                        : content
                    if let preview = nonEmpty(preview) {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Text(forumEntryMetadataLine(entry))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func forumRepliesWindowBlock(categoryID: String) -> some View {
        if let selectedEntryID = selectedForumEntryIDByCategoryID[categoryID] {
            if loadingForumEntryIDs.contains(selectedEntryID), forumRepliesByEntryID[selectedEntryID] == nil {
                ProgressView("Lade Antworten ...")
                    .controlSize(.small)
            } else if let replies = forumRepliesByEntryID[selectedEntryID], !replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Antworten", systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(replies) { reply in
                            forumReplyRow(reply)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            } else if let errorText = forumReplyErrorsByEntryID[selectedEntryID] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine Antworten zu diesem Thema gefunden.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Waehle ein Thema aus, um Antworten zu sehen.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func forumReplyRow(_ reply: ForumEntryDTO) -> some View {
        let bubbleColor = Color.accentColor.opacity(0.11)

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                if let content = nonEmpty(reply.content) {
                    let preview = content.contains("<") && content.contains(">")
                        ? plainText(fromHTML: content)
                        : content
                    Text(nonEmpty(preview) ?? "(leer)")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                } else {
                    Text("(leer)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(forumEntryMetadataLine(reply))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func filesBlock(for course: CourseDTO) -> some View {
        let contextKey = activeFileContextKey(for: course.id)
        let folders = foldersByContextKey[contextKey] ?? []
        let files = filesByContextKey[contextKey] ?? []
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.files.id)
        let filteredFolders = query.isEmpty ? folders : folders.filter { folder in
            containsSearch(
                [
                    nonEmpty(folder.name),
                    nonEmpty(folder.details),
                    folder.id
                ]
                .compactMap { $0 }
                .joined(separator: " "),
                query: query
            )
        }
        let filteredFiles = query.isEmpty ? files : files.filter { file in
            containsSearch(
                [
                    nonEmpty(file.name),
                    nonEmpty(file.description),
                    nonEmpty(file.ownerName),
                    nonEmpty(file.mimeType),
                    file.id
                ]
                .compactMap { $0 }
                .joined(separator: " "),
                query: query
            )
        }
        let hasContent = !folders.isEmpty || !files.isEmpty
        let hasFilteredContent = !filteredFolders.isEmpty || !filteredFiles.isEmpty

        if isLoadingFiles, foldersByContextKey[contextKey] == nil, filesByContextKey[contextKey] == nil {
            ProgressView("Lade Dateien ...")
                .controlSize(.small)
        } else if hasContent {
            if !hasFilteredContent {
                Text(detailSearchNoResultsText(for: CourseDetailSection.files.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let breadcrumb = folderBreadcrumbText(for: course.id) {
                        HStack(spacing: 10) {
                            Text(breadcrumb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Button("Zurueck") {
                                openParentFolder(for: course.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Wurzel") {
                                openRootFolder(for: course.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    ForEach(filteredFolders) { folder in
                        folderRow(folder, courseID: course.id)
                    }

                    ForEach(filteredFiles) { fileRef in
                        fileRow(fileRef, contextKey: contextKey)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 140)
            }
        } else if let errorText = fileErrorsByContextKey[contextKey] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Dateien oder Ordner gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func folderRow(_ folder: FolderDTO, courseID: String) -> some View {
        Button {
            openFolder(folder, for: courseID)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(nonEmpty(folder.name) ?? "Ordner \(folder.id)")
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    if let details = nonEmpty(folder.details) {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    func fileRow(_ fileRef: CourseFileRefDTO, contextKey: String) -> some View {
        let canPreview = fileRef.isReadable ?? fileRef.isDownloadable ?? true
        let canDownload = fileRef.isDownloadable ?? fileRef.isReadable ?? true

        return HStack(alignment: .top, spacing: 10) {
            Button {
                previewFileViaApplePreview(fileRef, contextKey: contextKey)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName(forMIMEType: fileRef.mimeType))
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(nonEmpty(fileRef.name) ?? "Datei \(fileRef.id)")
                            .font(.body.weight(.medium))
                            .lineLimit(2)

                        Text(fileMetadataLine(fileRef))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let description = nonEmpty(fileRef.description) {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if let downloadError = fileDownloadErrorsByFileID[fileRef.id] {
                            Text(downloadError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }

                        if let previewError = filePreviewErrorsByFileID[fileRef.id] {
                            Text(previewError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canPreview || previewingFileIDs.contains(fileRef.id))
            .help(canPreview ? "Apple Vorschau (Quick Look) anzeigen" : "Datei ist nicht lesbar")

            if previewingFileIDs.contains(fileRef.id) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
            }

            Button {
                downloadFileViaAPI(fileRef, contextKey: contextKey)
            } label: {
                if downloadingFileIDs.contains(fileRef.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .buttonStyle(.borderless)
            .disabled(!canDownload || downloadingFileIDs.contains(fileRef.id))
            .help(canDownload ? "Datei ueber API herunterladen" : "Datei ist nicht downloadbar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    func chatsBlock(for course: CourseDTO) -> some View {
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.chat.id)

        if isLoadingChats, chatsByCourseID[course.id] == nil {
            ProgressView("Lade Chat ...")
                .controlSize(.small)
        } else if let threads = chatsByCourseID[course.id], !threads.isEmpty {
            let filteredThreads = query.isEmpty ? threads : threads.filter { thread in
                containsSearch(
                    [
                        thread.name,
                        chatPreviewText(thread),
                        chatMetadataLine(thread),
                        thread.id
                    ]
                    .compactMap { $0 }
                    .joined(separator: " "),
                    query: query
                )
            }

            if filteredThreads.isEmpty {
                Text(detailSearchNoResultsText(for: CourseDetailSection.chat.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Unterhaltungen", systemImage: "list.bullet.bubble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredThreads) { thread in
                                chatRow(thread, courseID: course.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                    let selectedID = selectedChatThreadIDByCourseID[course.id]
                    if selectedID == nil || filteredThreads.contains(where: { $0.id == selectedID }) {
                        chatWindowBlock(for: course.id)
                    } else {
                        Text("Der aktuell ausgewaehlte Thread passt nicht zum Filter.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if let errorText = chatErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Chat-Threads gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func chatRow(_ thread: StudIPResourceRepository.CourseChatThread, courseID: String) -> some View {
        let isSelected = selectedChatThreadIDByCourseID[courseID] == thread.id

        return Button {
            selectedChatThreadIDByCourseID[courseID] = thread.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.2))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: thread.isFollowed == true ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.name)
                            .font(.body.weight(.medium))
                            .lineLimit(2)

                        if let preview = chatPreviewText(thread) {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    if let unseen = thread.unseenComments, unseen > 0 {
                        Text("\(unseen)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                Text(chatMetadataLine(thread))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if thread.isCommentable == true { smallBadge("Kommentierbar") }
                    if thread.isWritable == true { smallBadge("Schreibbar") }
                    if thread.isReadable == true { smallBadge("Lesbar") }
                    if thread.isFollowed == true { smallBadge("Abonniert") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func chatWindowBlock(for courseID: String) -> some View {
        if let threadID = selectedChatThreadIDByCourseID[courseID] {
            if loadingChatThreadIDs.contains(threadID), chatMessagesByThreadID[threadID] == nil {
                ProgressView("Lade Chatfenster ...")
                    .controlSize(.small)
            } else if let messages = chatMessagesByThreadID[threadID], !messages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Nachrichten", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            chatMessageRow(message)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            } else if let errorText = chatMessageErrorsByThreadID[threadID] {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine Nachrichten in diesem Chat.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Waehle einen Thread aus, um das Chatfenster zu laden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func chatMessageRow(_ message: BlubberPostingDTO) -> some View {
        let alignTrailing = abs(message.id.hashValue) % 4 == 0
        let bubbleColor = alignTrailing ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1)

        return HStack(alignment: .top, spacing: 0) {
            if alignTrailing {
                Spacer(minLength: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(chatMessageText(message))
                    .font(.callout)
                    .textSelection(.enabled)

                Text(chatMessageMetadataLine(message))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !alignTrailing {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignTrailing ? .trailing : .leading)
    }

    func smallBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.18))
            .clipShape(Capsule())
    }

    @ViewBuilder
    func wikisBlock(for course: CourseDTO) -> some View {
        let query = normalizedDetailSearchQuery(for: CourseDetailSection.wiki.id)

        if isLoadingWikis, wikisByCourseID[course.id] == nil {
            ProgressView("Lade Wiki ...")
                .controlSize(.small)
        } else if let pages = wikisByCourseID[course.id], !pages.isEmpty {
            let filteredPages = query.isEmpty ? pages : pages.filter { page in
                containsSearch(
                    [
                        page.keyword,
                        wikiPreviewText(page),
                        wikiMetadataLine(page),
                        wikiContentText(page),
                        page.id
                    ]
                    .compactMap { $0 }
                    .joined(separator: " "),
                    query: query
                )
            }

            if filteredPages.isEmpty {
                Text(detailSearchNoResultsText(for: CourseDetailSection.wiki.id))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredPages) { page in
                            wikiRow(page, courseID: course.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 100)

                    let selectedID = selectedWikiPageIDByCourseID[course.id]
                    if selectedID == nil || filteredPages.contains(where: { $0.id == selectedID }) {
                        wikiWindowBlock(for: course.id)
                    } else {
                        Text("Die aktuell ausgewaehlte Wiki-Seite passt nicht zum Filter.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if let errorText = wikiErrorsByCourseID[course.id] {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Keine Wiki-Seiten gefunden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func wikiRow(_ page: StudIPResourceRepository.CourseWikiPage, courseID: String) -> some View {
        let isSelected = selectedWikiPageIDByCourseID[courseID] == page.id

        return Button {
            selectedWikiPageIDByCourseID[courseID] = page.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "book.pages")
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.keyword)
                            .font(.body.weight(.medium))
                            .lineLimit(2)

                        if let preview = wikiPreviewText(page) {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }

                Text(wikiMetadataLine(page))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func wikiWindowBlock(for courseID: String) -> some View {
        if let pages = wikisByCourseID[courseID], !pages.isEmpty {
            if let selectedPage = selectedWikiPage(for: courseID, pages: pages) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedPage.keyword)
                        .font(.headline)
                        .lineLimit(2)

                    Text(wikiMetadataLine(selectedPage))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(wikiContentText(selectedPage))
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 120)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Waehle eine Wiki-Seite aus, um den Inhalt zu sehen.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Kein Wiki-Inhalt vorhanden.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
