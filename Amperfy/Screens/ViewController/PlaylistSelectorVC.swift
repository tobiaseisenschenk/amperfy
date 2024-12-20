//
//  PlaylistSelectorVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 09.03.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import CoreData
import AmperfyKit
import PromiseKit

enum AddToPlaylistSelectMode {
    case single
    case multi
}

class PlaylistSelectorVC: SingleFetchedResultsTableViewController<PlaylistMO> {

    override var sceneTitle: String? { "Playlists" }

    var itemsToAdd: [AbstractPlayable]?
    private var selectedPlaylits = [Playlist]()

    private var fetchedResultsController: PlaylistSelectorFetchedResultsController!
    private var sortType: PlaylistSortType = .name
    private var selectMode = AddToPlaylistSelectMode.single
    private var optionsButton: UIBarButtonItem!
    private var closeButton: UIBarButtonItem!
    private var selectBarButton: UIBarButtonItem!
    private var addBarButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()

        optionsButton = SortBarButton()

        appDelegate.userStatistics.visited(.playlistSelector)
        
        change(sortType: appDelegate.storage.settings.playlistsSortSetting)
        
        configureSearchController(placeholder: "Search in \"Playlists\"", showSearchBarAtEnter: true)
        tableView.register(nibName: PlaylistTableCell.typeName)
        tableView.rowHeight = PlaylistTableCell.rowHeight
        tableView.estimatedRowHeight = PlaylistTableCell.rowHeight

        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.size.width, height: NewPlaylistTableHeader.frameHeight))
        if let newPlaylistTableHeaderView = ViewCreator<NewPlaylistTableHeader>.createFromNib(withinFixedFrame: CGRect(x: 0, y: 0, width: view.bounds.size.width, height: NewPlaylistTableHeader.frameHeight)) {
            tableView.tableHeaderView?.addSubview(newPlaylistTableHeaderView)
        }
        
        navigationController?.setToolbarHidden(false, animated: false)
        let flexible = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.flexibleSpace, target: self, action: nil)
        selectBarButton = UIBarButtonItem(title: "Select", style: .plain, target: self, action: #selector(selectBarButtonPressed))
        addBarButton = UIBarButtonItem(image: .plus, style: .plain, target: self, action: #selector(addBarButtonPressed))
        self.toolbarItems = [selectBarButton, flexible, addBarButton]
        refreshAddButton()
    }

    func change(sortType: PlaylistSortType) {
        self.sortType = sortType
        // sortType will not be saved permanently. This behaviour differs from PlaylistsVC
        singleFetchedResultsController?.clearResults()
        tableView.reloadData()
        fetchedResultsController = PlaylistSelectorFetchedResultsController(coreDataCompanion: appDelegate.storage.main, sortType: sortType, isGroupedInAlphabeticSections: sortType.asSectionIndexType != .none)
        singleFetchedResultsController = fetchedResultsController
        tableView.reloadData()
        updateRightBarButtonItems()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateRightBarButtonItems()
        guard appDelegate.storage.settings.isOnlineMode else { return }
        firstly {
            self.appDelegate.librarySyncer.syncDownPlaylistsWithoutSongs()
        }.catch { error in
            self.appDelegate.eventLogger.report(topic: "Playlists Sync", error: error)
        }
    }
    
    func updateRightBarButtonItems() {
        closeButton = CloseBarButton(target: self, selector: #selector(cancelBarButtonPressed))
        optionsButton.menu = createSortButtonMenu()
#if targetEnvironment(macCatalyst)
        navigationItem.rightBarButtonItem = optionsButton
        navigationItem.leftBarButtonItem = closeButton
#else
        navigationItem.rightBarButtonItems = [closeButton, optionsButton]
#endif
    }
    
    @IBAction func addBarButtonPressed(_ sender: UIBarButtonItem) {
        addSongsToSelectedPlaylists()
        refreshAddButton()
        dismiss()
    }
    
    func addSongsToSelectedPlaylists() {
        guard let items = itemsToAdd else { return }
        let songsToAdd = items.compactMap{ $0.asSong }
        var syncPromises = [() -> Promise<Void>]()

        syncPromises = selectedPlaylits.compactMap { playlist in
            { return firstly {
                self.appDelegate.librarySyncer.syncUpload(playlistToAddSongs: playlist, songs: songsToAdd)
            }.then {
                playlist.append(playables: songsToAdd)
                return Promise.value
            }}
        }
        
        firstly {
            syncPromises.resolveSequentially()
        }
        .catch { error in
            self.appDelegate.eventLogger.report(topic: "Playlist Add Songs", error: error)
        }
          
        selectedPlaylits.removeAll()
    }
    
    @IBAction func selectBarButtonPressed(_ sender: Any) {
        selectMode = ((selectMode == .single) ? .multi : .single)
        selectBarButton.isSelected = (selectMode == .multi)
        refreshAddButton()
        selectedPlaylits.removeAll()
        tableView.reloadData()
    }
    
    func refreshAddButton() {
        addBarButton.isEnabled = !selectedPlaylits.isEmpty
    }
    
    @IBAction func cancelBarButtonPressed(_ sender: UIBarButtonItem) {
        dismiss()
    }
    
    private func createSortButtonMenu() -> UIMenu {
        let sortByName = UIAction(title: "Name", image: sortType == .name ? .check : nil, handler: { _ in
            self.change(sortType: .name)
            self.updateSearchResults(for: self.searchController)
            self.appDelegate.notificationHandler.post(name: .fetchControllerSortChanged, object: nil, userInfo: nil)
        })
        let sortByLastTimePlayed = UIAction(title: "Last time played", image: sortType == .lastPlayed ? .check : nil, handler: { _ in
            self.change(sortType: .lastPlayed)
            self.updateSearchResults(for: self.searchController)
            self.appDelegate.notificationHandler.post(name: .fetchControllerSortChanged, object: nil, userInfo: nil)
        })
        let sortByChangeDate = UIAction(title: "Change date", image: sortType == .lastChanged ? .check : nil, handler: { _ in
            self.change(sortType: .lastChanged)
            self.updateSearchResults(for: self.searchController)
            self.appDelegate.notificationHandler.post(name: .fetchControllerSortChanged, object: nil, userInfo: nil)
        })
        let sortByDuration = UIAction(title: "Duration", image: sortType == .duration ? .check : nil, handler: { _ in
            self.change(sortType: .duration)
            self.updateSearchResults(for: self.searchController)
            self.appDelegate.notificationHandler.post(name: .fetchControllerSortChanged, object: nil, userInfo: nil)
        })
        return UIMenu(title: "Sort", image: .sort, options: [], children: [sortByName, sortByLastTimePlayed, sortByChangeDate, sortByDuration])
    }
    
    private func dismiss() {
        searchController.dismiss(animated: false, completion: nil)
        dismiss(animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: PlaylistTableCell = dequeueCell(for: tableView, at: indexPath)
        let playlist = fetchedResultsController.getWrappedEntity(at: indexPath)
        cell.display(playlist: playlist, rootView: nil)
        
        if selectMode == .multi {
            let isMarked = (selectedPlaylits.firstIndex(where: { $0 == playlist }) != nil)
            let img = UIImageView(image: isMarked ? .checkmark : .circle)
            img.tintColor = isMarked ? appDelegate.storage.settings.themePreference.asColor : .secondaryLabelColor
            cell.accessoryView = img
        } else {
            cell.accessoryView = nil
        }
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let playlist = fetchedResultsController.getWrappedEntity(at: indexPath)
        
        let markedIndex = selectedPlaylits.firstIndex { $0 == playlist }
        if let markedIndex = markedIndex {
            selectedPlaylits.remove(at: markedIndex)
        } else {
            selectedPlaylits.append(playlist)
        }
        tableView.reconfigureRows(at: [indexPath])
        
        if selectMode == .single {
            addSongsToSelectedPlaylists()
            dismiss()
        } else {
            refreshAddButton()
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == Segues.toPlaylistDetail.rawValue {
            let vc = segue.destination as! PlaylistDetailVC
            let playlist = sender as? Playlist
            vc.playlist = playlist
        }
    }

    override func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text ?? ""
        fetchedResultsController.search(searchText: searchText)
        tableView.reloadData()
    }
    
}
