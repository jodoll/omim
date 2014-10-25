
#import "ActiveMapsVC.h"
#import "CustomAlertView.h"
#import "Statistics.h"
#import "MapCell.h"
#import "BadgeView.h"

@interface ActiveMapsVC () <ActiveMapsObserverProtocol>

@property (nonatomic) BadgeView * outOfDateBadge;
@property (nonatomic) ActiveMapsLayout::TGroup selectedGroup;

@end

@implementation ActiveMapsVC
{
  ActiveMapsObserver * m_mapsObserver;
  int m_mapsObserverSlotId;
}

- (id)init
{
  self = [super init];

  self.title = L(@"downloader_downloaded_maps");

  __weak ActiveMapsVC * weakSelf = self;
  m_mapsObserver = new ActiveMapsObserver(weakSelf);
  m_mapsObserverSlotId = self.mapsLayout.AddListener(m_mapsObserver);

  return self;
}

- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];

  if (self.isMovingFromParentViewController)
    self.mapsLayout.RemoveListener(m_mapsObserverSlotId);
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  [self refreshTopRightButton];
}

- (void)outOfDateCountriesCountChanged:(NSNotification *)notification
{
  self.outOfDateBadge.value = [[notification userInfo][@"OutOfDate"] integerValue];
}

- (void)refreshTopRightButton
{
  UIBarButtonItem * item;
  if (self.mapsLayout.IsDownloadingActive())
    item = [[UIBarButtonItem alloc] initWithTitle:L(@"downloader_cancel_all") style:UIBarButtonItemStylePlain target:self action:@selector(cancelAllMaps:)];
  else if (self.mapsLayout.GetOutOfDateCount() > 0)
    item = [[UIBarButtonItem alloc] initWithTitle:L(@"downloader_update_all") style:UIBarButtonItemStylePlain target:self action:@selector(updateAllMaps:)];

  [self.navigationItem setRightBarButtonItem:item animated:YES];
}

- (void)updateAllMaps:(id)sender
{
  self.mapsLayout.UpdateAll();
}

- (void)cancelAllMaps:(id)sender
{
  self.mapsLayout.CancelAll();
}

#pragma mark - Helpers

- (ActiveMapsLayout &)mapsLayout
{
  return GetFramework().GetCountryTree().GetActiveMapLayout();
}

- (ActiveMapsLayout::TGroup)groupWithSection:(NSInteger)section
{
  ASSERT(section < (NSInteger)ActiveMapsLayout::TGroup::EGroupCount, ());
  return static_cast<ActiveMapsLayout::TGroup>(section);
}

- (MapCell *)cellAtPosition:(int)position inGroup:(ActiveMapsLayout::TGroup const &)group
{
  return (MapCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:position inSection:(NSInteger)group]];
}

- (void)markSelectedMapIndexPath:(NSIndexPath *)indexPath
{
  self.selectedPosition = indexPath.row;
  self.selectedGroup = [self groupWithSection:indexPath.section];
}

- (void)configureSizeLabelOfMapCell:(MapCell *)cell position:(int)position group:(ActiveMapsLayout::TGroup const &)group status:(TStatus const &)status options:(TMapOptions const &)options
{
  if (status == TStatus::ENotDownloaded)
  {
    LocalAndRemoteSizeT const size = self.mapsLayout.GetRemoteCountrySizes(group, position);
    cell.sizeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self formattedMapSize:size.first], [self formattedMapSize:size.second]];
  }
  else if (status == TStatus::EOnDisk || status == TStatus::EOnDiskOutOfDate)
    cell.sizeLabel.text = [self formattedMapSize:self.mapsLayout.GetCountrySize(group, position, options).second];
  else if (status == TStatus::EOutOfMemFailed || status == TStatus::EDownloadFailed || status == TStatus::EDownloading || status == TStatus::EInQueue)
    cell.sizeLabel.text = [self formattedMapSize:self.mapsLayout.GetDownloadableCountrySize(group, position).second];
}

#pragma mark - DownloaderParentVC virtual methods implementation

- (NSString *)parentTitle
{
  return nil;
}

- (NSString *)selectedMapName
{
  return [NSString stringWithUTF8String:self.mapsLayout.GetCountryName(self.selectedGroup, self.selectedPosition).c_str()];
}

- (NSString *)selectedMapGuideName
{
  guides::GuideInfo info;
  if (self.mapsLayout.GetGuideInfo(self.selectedGroup, self.selectedPosition, info))
  {
    string const lang = languages::GetCurrentNorm();
    return [NSString stringWithUTF8String:info.GetAdTitle(lang).c_str()];
  }
  return nil;
}

- (size_t)selectedMapSizeWithOptions:(storage::TMapOptions)options
{
  return self.mapsLayout.GetCountrySize(self.selectedGroup, self.selectedPosition, options).second;
}

- (TStatus)selectedMapStatus
{
  return self.mapsLayout.GetCountryStatus(self.selectedGroup, self.selectedPosition);
}

- (TMapOptions)selectedMapOptions
{
  return self.mapsLayout.GetCountryOptions(self.selectedGroup, self.selectedPosition);
}

- (void)performAction:(DownloaderAction)action
{
  switch (action)
  {
    case DownloaderActionDownloadAll:
    case DownloaderActionDownloadMap:
    case DownloaderActionDownloadCarRouting:
      if ([self canDownloadSelectedMap])
        self.mapsLayout.DownloadMap(self.selectedGroup, self.selectedPosition, self.selectedInActionSheetOptions);
      break;

    case DownloaderActionDeleteAll:
    case DownloaderActionDeleteMap:
    case DownloaderActionDeleteCarRouting:
      self.mapsLayout.DeleteMap(self.selectedGroup, self.selectedPosition, self.selectedInActionSheetOptions);
      break;

    case DownloaderActionCancelDownloading:
      self.mapsLayout.CancelDownloading(self.selectedGroup, self.selectedPosition);
      break;

    case DownloaderActionZoomToCountry:
      self.mapsLayout.ShowMap(self.selectedGroup, self.selectedPosition);
      [[Statistics instance] logEvent:@"Show Map From Download Countries Screen"];
      [self.navigationController popToRootViewControllerAnimated:YES];
      break;

    case DownloaderActionShowGuide:
      guides::GuideInfo info;
      if (self.mapsLayout.GetGuideInfo(self.selectedGroup, self.selectedPosition, info))
        [self openGuideWithInfo:info];
      break;
  }
}

#pragma mark - TableView

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
  ActiveMapsLayout::TGroup const group = [self groupWithSection:section];

  if (group == ActiveMapsLayout::TGroup::ENewMap)
    return nil;

  UIView * view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 40)];
  view.clipsToBounds = YES;
  UILabel * label = [[UILabel alloc] initWithFrame:view.bounds];
  label.font = [UIFont fontWithName:@"HelveticaNeue" size:13];
  label.backgroundColor = [UIColor clearColor];

  if (group == ActiveMapsLayout::TGroup::EOutOfDate)
    label.text = L(@"downloader_outdated_maps").uppercaseString;
  else if (group == ActiveMapsLayout::TGroup::EUpToDate)
    label.text = L(@"downloader_uptodate_maps").uppercaseString;

  [label sizeToIntegralFit];
  [view addSubview:label];
  label.minX = 13;
  label.maxY = view.height - 5;
  if (group == ActiveMapsLayout::TGroup::EOutOfDate)
  {
    BadgeView * badge = [[BadgeView alloc] init];
    badge.value = self.mapsLayout.GetOutOfDateCount() + 25;
    badge.center = CGPointMake(label.maxX + badge.width - 3, label.midY - 1.0 / [UIScreen mainScreen].scale);
    [view addSubview:badge];
    self.outOfDateBadge = badge;
  }
  return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
  ActiveMapsLayout::TGroup const group = [self groupWithSection:section];
  if (group == ActiveMapsLayout::TGroup::EOutOfDate || group == ActiveMapsLayout::TGroup::EUpToDate)
    return self.mapsLayout.GetCountInGroup(group) == 0 ? 0.001 : 42;
  else
    return 0.001;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
  return 0.001;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
  return (NSInteger)ActiveMapsLayout::TGroup::EGroupCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  return self.mapsLayout.GetCountInGroup([self groupWithSection:section]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  MapCell * cell = [tableView dequeueReusableCellWithIdentifier:[MapCell className]];
  if (!cell)
    cell = [[MapCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:[MapCell className]];

  int const position = indexPath.row;
  ActiveMapsLayout::TGroup const group = [self groupWithSection:indexPath.section];
  TStatus const status = self.mapsLayout.GetCountryStatus(group, position);
  TMapOptions const options = self.mapsLayout.GetCountryOptions(group, position);

  cell.titleLabel.text = [NSString stringWithUTF8String:self.mapsLayout.GetCountryName(group, position).c_str()];
  cell.parentMode = NO;
  cell.status = status;
  cell.options = options;
  cell.delegate = self;
  cell.badgeView.value = 0;

  if (status == TStatus::EOutOfMemFailed || status == TStatus::EDownloadFailed || status == TStatus::EDownloading || status == TStatus::EInQueue)
  {
    LocalAndRemoteSizeT const size = self.mapsLayout.GetDownloadableCountrySize(group, position);
    cell.downloadProgress = (double)size.first / size.second;
  }
  [self configureSizeLabelOfMapCell:cell position:position group:group status:status options:options];

  return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
  TStatus const status = self.mapsLayout.GetCountryStatus([self groupWithSection:indexPath.section], indexPath.row);
  return status == TStatus::EOnDisk || status == TStatus::EOnDiskOutOfDate;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
  if (editingStyle == UITableViewCellEditingStyleDelete)
  {
    int const position = indexPath.row;
    ActiveMapsLayout::TGroup const group = [self groupWithSection:indexPath.section];
    TMapOptions const options = self.mapsLayout.GetCountryOptions(group, position);
    self.mapsLayout.DeleteMap(group, position, options);
    [tableView setEditing:NO animated:YES];
  }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  [self markSelectedMapIndexPath:indexPath];

  MapCell * cell = [self cellAtPosition:self.selectedPosition inGroup:self.selectedGroup];
  UIActionSheet * actionSheet = [self actionSheetToPerformActionOnSelectedMap];
  [actionSheet showFromRect:cell.frame inView:cell.superview animated:YES];

  [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
  return [MapCell cellHeight];
}

#pragma mark - MapCellDelegate

- (void)mapCellDidStartDownloading:(MapCell *)cell
{
  [self markSelectedMapIndexPath:[self.tableView indexPathForCell:cell]];
  TStatus const status = [self selectedMapStatus];
  if (status == TStatus::EDownloadFailed || status == TStatus::EOutOfMemFailed)
    if ([self canDownloadSelectedMap])
      self.mapsLayout.RetryDownloading(self.selectedGroup, self.selectedPosition);
}

- (void)mapCellDidCancelDownloading:(MapCell *)cell
{
  NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];
  self.selectedPosition = indexPath.row;
  self.selectedGroup = [self groupWithSection:indexPath.section];

  [[self actionSheetToCancelDownloadingSelectedMap] showFromRect:cell.frame inView:cell.superview animated:YES];
}

#pragma mark - ActiveMaps core callbacks

- (void)countryStatusChangedAtPosition:(int)position inGroup:(ActiveMapsLayout::TGroup const &)group
{
  [self refreshTopRightButton];

  MapCell * cell = [self cellAtPosition:position inGroup:group];

  TStatus const status = self.mapsLayout.GetCountryStatus(group, position);
  TMapOptions const options = self.mapsLayout.GetCountryOptions(group, position);
  [self configureSizeLabelOfMapCell:cell position:position group:group status:status options:options];
  [cell setStatus:self.mapsLayout.GetCountryStatus(group, position) options:self.mapsLayout.GetCountryOptions(group, position) animated:YES];

  self.outOfDateBadge.value = self.mapsLayout.GetOutOfDateCount();
}

- (void)countryOptionsChangedAtPosition:(int)position inGroup:(ActiveMapsLayout::TGroup const &)group
{
  MapCell * cell = [self cellAtPosition:position inGroup:group];

  TStatus const status = self.mapsLayout.GetCountryStatus(group, position);
  TMapOptions const options = self.mapsLayout.GetCountryOptions(group, position);
  [self configureSizeLabelOfMapCell:cell position:position group:group status:status options:options];
  [cell setStatus:self.mapsLayout.GetCountryStatus(group, position) options:self.mapsLayout.GetCountryOptions(group, position) animated:YES];
}

- (void)countryGroupChangedFromPosition:(int)oldPosition inGroup:(ActiveMapsLayout::TGroup const &)oldGroup toPosition:(int)newPosition inGroup:(ActiveMapsLayout::TGroup const &)newGroup
{
  if (oldGroup == newGroup && oldPosition == -1)
  {
    NSIndexPath * indexPath = [NSIndexPath indexPathForRow:newPosition inSection:(NSInteger)newGroup];
    [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
  }
  else if (oldGroup == newGroup && newPosition == -1)
  {
    NSIndexPath * indexPath = [NSIndexPath indexPathForRow:oldPosition inSection:(NSInteger)oldGroup];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
  }
  else if (oldGroup != newGroup && oldPosition >= 0 && newPosition >= 0)
  {
    NSIndexPath * oldIndexPath = [NSIndexPath indexPathForRow:oldPosition inSection:(NSInteger)oldGroup];
    NSIndexPath * newIndexPath = [NSIndexPath indexPathForRow:newPosition inSection:(NSInteger)newGroup];
    [self.tableView moveRowAtIndexPath:oldIndexPath toIndexPath:newIndexPath];
  }
}

- (void)countryDownloadingProgressChanged:(LocalAndRemoteSizeT const &)progress atPosition:(int)position inGroup:(ActiveMapsLayout::TGroup const &)group
{
  MapCell * cell = [self cellAtPosition:position inGroup:group];
  [cell setDownloadProgress:((double)progress.first / progress.second) animated:YES];
}

@end
