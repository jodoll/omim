#include "country.hpp"

#include "../base/logging.hpp"

#include "../base/std_serialization.hpp"

#include "../coding/streams_sink.hpp"
#include "../coding/file_reader.hpp"
#include "../coding/file_writer.hpp"
#include "../coding/file_container.hpp"

#include "../version/version.hpp"

#include "../platform/platform.hpp"

#include "../indexer/data_header.hpp"

#include "../std/fstream.hpp"
#include "../std/ctime.hpp"

namespace storage
{
  /// Simple check - compare url size with real file size on disk
  bool IsTileDownloaded(TTile const & tile)
  {
    uint64_t size = 0;
    if (!GetPlatform().GetFileSize(GetPlatform().WritablePathForFile(tile.first), size))
      return false;
    return true;//tile.second == size;
  }

  struct CountryBoundsCalculator
  {
    m2::RectD & m_bounds;
    CountryBoundsCalculator(m2::RectD & bounds) : m_bounds(bounds) {}
    void operator()(TTile const & tile)
    {
      feature::DataHeader header;
      FilesContainerR reader(GetPlatform().WritablePathForFile(tile.first));
      header.Load(reader.GetReader(HEADER_FILE_TAG));
      m_bounds.Add(header.GetBounds());
    }
  };

  m2::RectD Country::Bounds() const
  {
    m2::RectD bounds;
    std::for_each(m_tiles.begin(), m_tiles.end(), CountryBoundsCalculator(bounds));
    return bounds;
  }

  struct SizeCalculator
  {
    uint64_t & m_localSize;
    uint64_t & m_remoteSize;
    SizeCalculator(uint64_t & localSize, uint64_t & remoteSize)
      : m_localSize(localSize), m_remoteSize(remoteSize) {}
    void operator()(TTile const & tile)
    {
      if (IsTileDownloaded(tile))
        m_localSize += tile.second;
      m_remoteSize += tile.second;
    }
  };

  TLocalAndRemoteSize Country::Size() const
  {
    uint64_t localSize = 0;
    uint64_t remoteSize = 0;
    std::for_each(m_tiles.begin(), m_tiles.end(), SizeCalculator(localSize, remoteSize));
    return TLocalAndRemoteSize(localSize, remoteSize);
  }

  void Country::AddTile(TTile const & tile)
  {
    m_tiles.push_back(tile);
  }

  ////////////////////////////////////////////////////////////////////////

//  template <class TArchive> TArchive & operator << (TArchive & ar, storage::Country const & country)
//  {
//    ar << country.m_name;
//    ar << country.m_tiles;
//    return ar;
//  }

  inline bool IsCellId(string const & cellId)
  {
    size_t const size = cellId.size();
    if (size == 0)
      return false;
    for (size_t i = 0; i < size; ++i)
    {
      if (cellId[i] < '0' || cellId[i] > '3')
        return false;
    }
    return true;
  }

  bool LoadCountries(string const & countriesFile, TTilesContainer const & sortedTiles,
                     TCountriesContainer & countries)
  {
    // small prediction - are we using cells or simple countries?
    bool const cellsAreUsed = sortedTiles.size() > 1000;

    countries.Clear();
    ifstream stream(countriesFile.c_str());
    std::string line;
    Country * currentCountry = &countries.Value();
    while (stream.good())
    {
      std::getline(stream, line);
      if (line.empty())
        continue;

      // calculate spaces - depth inside the tree
      int spaces = 0;
      for (size_t i = 0; i < line.size(); ++i)
      {
        if (line[i] == ' ')
          ++spaces;
        else
          break;
      }
      switch (spaces)
      {
      case 0: // this is value for current tree node
        {
          TTilesContainer::const_iterator const first = sortedTiles.begin();
          TTilesContainer::const_iterator const last = sortedTiles.end();
          TTilesContainer::const_iterator found = lower_bound(first, last, TTile(line, 0));
          if (found != last && !(line < found->first))
            currentCountry->AddTile(TTile(found->first + DATA_FILE_EXTENSION, found->second));
        }
        break;
      case 1: // country group
      case 2: // country name
      case 3: // region
        {
          string const name = line.substr(spaces);
          currentCountry = &countries.AddAtDepth(spaces - 1, Country(name));
          if (!cellsAreUsed)
          { // we trying to load countries by name instead of square cell tiles
            TTilesContainer::const_iterator const first = sortedTiles.begin();
            TTilesContainer::const_iterator const last = sortedTiles.end();
            string const nameWithExt = name + DATA_FILE_EXTENSION;
            TTilesContainer::const_iterator found = lower_bound(
                first, last, TTile(nameWithExt, 0));
            if (found != last && !(nameWithExt < found->first))
              currentCountry->AddTile(*found);
          }
        }
        break;
      default:
        return false;
      }
    }
    return countries.SiblingsCount() > 0;
  }

  void SaveTiles(string const & file, int32_t level, TDataFiles const & cellFiles, TCommonFiles const & commonFiles)
  {
    FileWriter writer(file);
    stream::SinkWriterStream<Writer> wStream(writer);

    // save version - it's equal to current date in GMT
    time_t rawTime = time(NULL);
    tm * pTm = gmtime(&rawTime);
    uint32_t const version = (pTm->tm_year - 100) * 10000 + (pTm->tm_mon + 1) * 100 + pTm->tm_mday;
    wStream << static_cast<uint32_t>(version);
    wStream << level;
    wStream << cellFiles;
    wStream << commonFiles;
  }

  bool LoadTiles(TTilesContainer & tiles, string const & tilesFile, uint32_t & dataVersion)
  {
    tiles.clear();

    try
    {
      FileReader fileReader(tilesFile);
      ReaderSource<FileReader> source(fileReader);
      stream::SinkReaderStream<ReaderSource<FileReader> > stream(source);

      TDataFiles dataFiles;
      TCommonFiles commonFiles;

      int32_t level = -1;
      stream >> dataVersion;
      stream >> level;
      stream >> dataFiles;
      stream >> commonFiles;

      tiles.reserve(dataFiles.size() + commonFiles.size());

      for (TDataFiles::iterator it = dataFiles.begin(); it != dataFiles.end(); ++it)
        tiles.push_back(TTile(CountryCellId::FromBitsAndLevel(it->first, level).ToString(), it->second));
      for (TCommonFiles::iterator it = commonFiles.begin(); it != commonFiles.end(); ++it)
        tiles.push_back(TTile(it->first, it->second));

      sort(tiles.begin(), tiles.end());
    }
    catch (RootException const & e)
    {
      LOG(LWARNING, ("Can't read tiles file", e.what()));
      return false;
    }

    return true;
  }

//  void SaveCountries(TCountriesContainer const & countries, Writer & writer)
//  {
//    stream::SinkWriterStream<Writer> wStream(writer);
//    wStream << MAPS_MAJOR_VERSION_BINARY_FORMAT;
//    wStream << countries;
//  }
}
