//
//  TabView.swift
//  Synth
//

import NucleantUI

/// Pages under a row of tabs, one page shown at a time: the chosen tab is
/// lit, and a click on another shows its page instead.
///
///     TabView(selection: $page, pages: ControlPage.allCases, title: \.title) { page in
///         Controls(model: model, page: page)
///     }
@View
struct TabView<Page: Hashable, Content: View> {
    @Binding var selection: Page
    let pages: [Page]
    let title: (Page) -> String
    let content: (Page) -> Content

    init(selection: Binding<Page>, pages: some Sequence<Page>, title: @escaping (Page) -> String,
         _viewID: ViewID = #viewID, @ViewBuilder content: @escaping (Page) -> Content) {
        self._selection = selection
        self.pages = Array(pages)
        self.title = title
        self.content = content
        self._viewID = _viewID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(pages, id: \.self) { page in
                    let chosen = page == selection
                    Text(title(page).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(chosen ? Theme.accent : Theme.label)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(chosen ? Theme.panel : Theme.background)
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = page }
                }
            }
            content(selection)
        }
    }
}
