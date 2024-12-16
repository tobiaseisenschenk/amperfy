//
//  AudioPlayer.swift
//  AmperfyKit
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

import Foundation
import AVFoundation
import MediaPlayer
import os.log

public class AudioPlayer: NSObject, BackendAudioPlayerNotifiable  {
    
    public static let replayInsteadPlayPreviousTimeInSec = 5.0
    static let progressTimeStartThreshold: Double = 15.0
    static let progressTimeEndThreshold: Double = 15.0
    
    var currentlyPlaying: AbstractPlayable? {
        return queueHandler.currentlyPlaying
    }
    var currentMusicItem: AbstractPlayable? {
        return queueHandler.currentMusicItem
    }
    var currentPodcastItem: AbstractPlayable? {
        return queueHandler.currentPodcastItem
    }
    var isShouldPauseAfterFinishedPlaying = false
    private var isContinueSongProgress = true

    private var playerStatus: PlayerStatusPersistent
    private var queueHandler: PlayQueueHandler
    private let backendAudioPlayer: BackendAudioPlayer
    private let settings: PersistentStorage.Settings
    private let userStatistics: UserStatistics
    private var notifierList = [MusicPlayable]()
    private var chromeCastPlayer: ChromecastPlayer

    init(coreData: PlayerStatusPersistent, queueHandler: PlayQueueHandler, backendAudioPlayer: BackendAudioPlayer, settings: PersistentStorage.Settings, userStatistics: UserStatistics, chromeCastPlayer: ChromecastPlayer) {
        self.playerStatus = coreData
        self.queueHandler = queueHandler
        self.backendAudioPlayer = backendAudioPlayer
        self.backendAudioPlayer.isAutoCachePlayedItems = coreData.isAutoCachePlayedItems
        self.settings = settings
        self.userStatistics = userStatistics
        self.chromeCastPlayer = chromeCastPlayer
        super.init()
        self.backendAudioPlayer.responder = self
        self.backendAudioPlayer.nextPlayablePreloadCB = { () in
            guard let nextPlayerIndex = self.nextPlayerIndex else { return nil }
            return self.queueHandler.getPlayable(at: nextPlayerIndex)
        }
    }

    func reinit(playerStatus: PlayerData, queueHandler: PlayQueueHandler) {
        self.playerStatus = playerStatus
        self.queueHandler = queueHandler
    }
    
    private func shouldCurrentItemReplayedInsteadOfPrevious() -> Bool {
        if !backendAudioPlayer.canBeContinued {
            return false
        }
        return backendAudioPlayer.elapsedTime >= Self.replayInsteadPlayPreviousTimeInSec
    }

    private func replayCurrentItem() {
        os_log(.debug, "Replay")
        if let currentPlayable = currentlyPlaying {
            insertIntoPlayer(playable: currentPlayable)
        }
        notifyItemStartedPlayingFromBeginning()
    }

    private func insertIntoPlayer(playable: AbstractPlayable) {
        userStatistics.playedItem(repeatMode: playerStatus.repeatMode, isShuffle: playerStatus.isShuffle)
        playable.countPlayed()
        backendAudioPlayer.requestToPlay(playable: playable, playbackRate: playerStatus.playbackRate, autoStartPlayback: !self.settings.isPlaybackStartOnlyOnPlay)
    }
    
    //BackendAudioPlayerNotifiable
    func notifyItemPreparationFinished() {
        notifyItemStartedPlayingFromBeginning()
        notifyItemStartedPlaying()
    }
    
    //BackendAudioPlayerNotifiable
    func didItemFinishedPlaying() {
        if isShouldPauseAfterFinishedPlaying {
            isShouldPauseAfterFinishedPlaying = false
            pause()
        } else if playerStatus.repeatMode == .single {
            replayCurrentItem()
        } else if !self.settings.isPlaybackStartOnlyOnPlay {
            playNext()
        }
    }
    
    func play() {
        if !backendAudioPlayer.canBeContinued {
            if let currentPlayable = currentlyPlaying {
                insertIntoPlayer(playable: currentPlayable)
            }
        } else {
            backendAudioPlayer.continuePlay()
            notifyItemStartedPlaying()
        }
        self.chromeCastPlayer.playRemote()
    }

    public func play(context: PlayContext) {
        os_log("play context \(context.index) \(context.name)")
        guard let activePlayable = context.getActivePlayable() else { return }
        let topUserQueueItem = queueHandler.userQueue.first
        let wasUserQueuePlaying = queueHandler.isUserQueuePlaying
        queueHandler.clearActiveQueue()
        queueHandler.appendActiveQueue(playables: context.playables)
        chromeCastPlayer.castQueue(playables: context.playables, startIndex: context.index, {})
        if context.type == .music {
            queueHandler.contextName = context.name
        }
        
        if queueHandler.isUserQueuePlaying {
            play(playerIndex: PlayerIndex(queueType: .next, index: context.index))
            if !wasUserQueuePlaying, let topUserQueueItem = topUserQueueItem {
                queueHandler.insertUserQueue(playables: [topUserQueueItem])
            }
        } else if context.index == 0 {
            insertIntoPlayer(playable: activePlayable)
        } else {
            play(playerIndex: PlayerIndex(queueType: .next, index: context.index-1))
        }
    }
    
    func play(playerIndex: PlayerIndex) {
        guard let playable = queueHandler.markAndGetPlayableAsPlaying(at: playerIndex) else {
            stop()
            return
        }
        isContinueSongProgress = false
        insertIntoPlayer(playable: playable)
    }
    
    func playPreviousOrReplay() {
        if shouldCurrentItemReplayedInsteadOfPrevious() {
            replayCurrentItem()
        } else {
            playPrevious()
        }
    }

    //BackendAudioPlayerNotifiable
    func playPrevious() {
        if !queueHandler.prevQueue.isEmpty {
            play(playerIndex: PlayerIndex(queueType: .prev, index: queueHandler.prevQueue.count-1))
        } else if playerStatus.repeatMode == .all, !queueHandler.nextQueue.isEmpty {
            play(playerIndex: PlayerIndex(queueType: .next, index: queueHandler.nextQueue.count-1))
        } else {
            replayCurrentItem()
        }
        chromeCastPlayer.playPrevious()
    }

    //BackendAudioPlayerNotifiable
    func playNext() {
        if let nextPlayerIndex = nextPlayerIndex {
            play(playerIndex: nextPlayerIndex)
        } else {
            stop()
        }
    }
        
    private var nextPlayerIndex: PlayerIndex? {
        if queueHandler.userQueue.count > 0 {
            return PlayerIndex(queueType: .user, index: 0)
        } else if queueHandler.nextQueue.count > 0 {
            chromeCastPlayer.playNext()
            return PlayerIndex(queueType: .next, index: 0)
        } else if playerStatus.repeatMode == .all, !queueHandler.prevQueue.isEmpty {
            return PlayerIndex(queueType: .prev, index: 0)
        } else {
            return nil
        }
    }
    
    func pause() {
        backendAudioPlayer.pause()
        self.chromeCastPlayer.pauseRemote()
        notifyItemPaused()
    }
    
    //BackendAudioPlayerNotifiable
    func stop() {
        isContinueSongProgress = false
        backendAudioPlayer.stop()
        playerStatus.stop()
        chromeCastPlayer.stopRemote()
        notifyPlayerStopped()
    }
    
    func stopButRemainIndex() {
        backendAudioPlayer.stop()
        chromeCastPlayer.stopRemote()
        notifyPlayerStopped()
    }
    
    func activateSongContinueProgress() {
        isContinueSongProgress = true
    }
    
    func togglePlayPause() {
        if(backendAudioPlayer.isPlaying) {
            pause()
        } else {
            play()
        }
    }
    
    private func seekToLastStoppedPlayTime() {
        if let playable = currentlyPlaying,
           playable.playProgress > 0,
           backendAudioPlayer.isErrorOccured || playable.isPodcastEpisode || isContinueSongProgress {
            backendAudioPlayer.seek(toSecond: Double(playable.playProgress))
            self.chromeCastPlayer.seekRemote(to: Double(playable.playProgress))
        }
        isContinueSongProgress = false
    }

    //BackendAudioPlayerNotifiable
    func didElapsedTimeChange() {
        notifyElapsedTimeChanged()
        if let currentItem = currentlyPlaying {
            savePlayInformation(of: currentItem)
        }
    }
    
    //BackendAudioPlayerNotifiable
    func didLyricsTimeChange(time: CMTime) {
        notifyLyricsTimeChanged(time: time)
    }
    
    private func savePlayInformation(of playable: AbstractPlayable) {
        let playDuration = backendAudioPlayer.duration
        let playProgress = backendAudioPlayer.elapsedTime
        if playDuration != 0.0, playProgress != 0.0, playable == currentlyPlaying {
            playable.playDuration = Int(playDuration)
            if playProgress > Self.progressTimeStartThreshold, playProgress < (playDuration - Self.progressTimeEndThreshold) {
                playable.playProgress = Int(playProgress)
            } else {
                playable.playProgress = 0
            }
        }
    }
    
    func addNotifier(notifier: MusicPlayable) {
        notifierList.append(notifier)
    }
    
    func removeAllNotifier() {
        notifierList.removeAll()
    }
    
    func notifyItemStartedPlayingFromBeginning() {
        for notifier in notifierList {
            notifier.didStartPlayingFromBeginning()
        }
        seekToLastStoppedPlayTime()
    }

    func notifyItemStartedPlaying() {
        for notifier in notifierList {
            notifier.didStartPlaying()
        }
    }
    
    //BackendAudioPlayerNotifiable
    func notifyErrorOccured(error: Error) {
        for notifier in notifierList {
            notifier.errorOccured(error: error)
        }
    }
    
    func notifyItemPaused() {
        for notifier in notifierList {
            notifier.didPause()
        }
    }
    
    func notifyPlayerStopped() {
        for notifier in notifierList {
            notifier.didStopPlaying()
        }
    }
    
    func notifyArtworkChanged() {
        for notifier in notifierList {
            notifier.didArtworkChange()
        }
    }
    
    func notifyElapsedTimeChanged() {
        for notifier in notifierList {
            notifier.didElapsedTimeChange()
        }
    }
    
    func notifyLyricsTimeChanged(time: CMTime) {
        for notifier in notifierList {
            notifier.didLyricsTimeChange(time: time)
        }
    }
    
    func notifyPlaylistUpdated() {
        for notifier in notifierList {
            notifier.didPlaylistChange()
        }
    }

    func notifyShuffleUpdated() {
        for notifier in notifierList {
            notifier.didShuffleChange()
        }
    }

    func notifyRepeatUpdated() {
        for notifier in notifierList {
            notifier.didRepeatChange()
        }
    }
    
    func notifyPlaybackRateUpdated() {
        for notifier in notifierList {
            notifier.didPlaybackRateChange()
        }
    }

}
