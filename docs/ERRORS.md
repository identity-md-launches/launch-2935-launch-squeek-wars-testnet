# Revert reason migration

The size adaptation replaces string reasons with parameterless custom errors. Each row retains the original failing condition and check order. Decode the selector with the affected contract ABI in [abi/](abi/); existing custom errors and Solidity panic codes are unchanged. Caller-visible module errors still propagate unchanged.

| Previous reason | New error |
| --- | --- |
| Academy too low | `AcademyTooLow()` |
| Already building target | `AlreadyBuildingTarget()` |
| Already in clan | `AlreadyInClan()` |
| Already registered or invalid player | `AlreadyRegisteredOrInvalidPlayer()` |
| Banner already owned | `BannerAlreadyOwned()` |
| Boost active or invalid resource | `BoostActiveOrInvalidResource()` |
| Building capped by Town Hall | `BuildingCappedByTownHall()` |
| Cannot cancel completed build | `CannotCancelCompletedBuild()` |
| Cannot join | `CannotJoin()` |
| Cannot raise capacity | `CannotRaiseCapacity()` |
| Cannot recall support | `CannotRecallSupport()` |
| Champion away | `ChampionAway()` |
| Clan Hall 3 required | `ClanHall3Required()` |
| Clan full or missing | `ClanFullOrMissing()` |
| Clan name taken | `ClanNameTaken()` |
| Daily raid limit | `DailyRaidLimit()` |
| Exponent out of bounds | `ExponentOutOfBounds()` |
| Field capped by Town Hall | `FieldCappedByTownHall()` |
| Founder leaves last | `FounderLeavesLast()` |
| Insufficient Burrow room | `InsufficientBurrowRoom()` |
| Insufficient champion points | `InsufficientChampionPoints()` |
| Insufficient storage | `InsufficientStorage()` |
| Insufficient troops | `InsufficientTroops()` |
| Invalid build slot | `InvalidBuildSlot()` |
| Invalid building | `InvalidBuilding()` |
| Invalid camp | `InvalidCamp()` |
| Invalid camp movement | `InvalidCampMovement()` |
| Invalid capacity | `InvalidCapacity()` |
| Invalid counter | `InvalidCounter()` |
| Invalid dependency | `InvalidDependency()` |
| Invalid exchange | `InvalidExchange()` |
| Invalid field | `InvalidField()` |
| Invalid field level | `InvalidFieldLevel()` |
| Invalid integral query | `InvalidIntegralQuery()` |
| Invalid movement | `InvalidMovement()` |
| Invalid name character | `InvalidNameCharacter()` |
| Invalid name length | `InvalidNameLength()` |
| Invalid refund | `InvalidRefund()` |
| Invalid slot | `InvalidSlot()` |
| Invalid support | `InvalidSupport()` |
| Invalid tier | `InvalidTier()` |
| Invalid town hall | `InvalidTownHall()` |
| Invalid training | `InvalidTraining()` |
| Invalid travel | `InvalidTravel()` |
| Invalid troop count | `InvalidTroopCount()` |
| Invalid unit | `InvalidUnit()` |
| Market required | `MarketRequired()` |
| Max level | `MaxLevel()` |
| Missing support | `MissingSupport()` |
| Missing target | `MissingTarget()` |
| Missing village | `MissingVillage()` |
| Movement not arrived | `MovementNotArrived()` |
| Name taken | `NameTaken()` |
| No plot available | `NoPlotAvailable()` |
| Not in clan | `NotInClan()` |
| Not invited | `NotInvited()` |
| Only founder invites | `OnlyFounderInvites()` |
| Only scouts reconnoitre | `OnlyScoutsReconnoitre()` |
| Peace cooldown | `PeaceCooldown()` |
| Points cannot be reassigned | `PointsCannotBeReassigned()` |
| Research Vault first | `ResearchVaultFirst()` |
| Research busy | `ResearchBusy()` |
| Research required | `ResearchRequired()` |
| Research tier 2 first | `ResearchTier2First()` |
| Scouts travel alone | `ScoutsTravelAlone()` |
| Shield already active | `ShieldAlreadyActive()` |
| Stat cap | `StatCap()` |
| Support still allied | `SupportStillAllied()` |
| Target protected | `TargetProtected()` |
| Training busy or missing village | `TrainingBusyOrMissingVillage()` |
| Training not ready | `TrainingNotReady()` |
