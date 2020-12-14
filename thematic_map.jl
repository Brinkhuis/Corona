# Packages
using CSV
using DataFrames
using Plots
using Shapefile
using ZipFile

# Create directorties
for dir in ["data", "downloads", "shapefiles", "output"]
    path = joinpath(pwd(), dir)
    if ~ispath(path)
        mkpath(path)
    end
end

# Helper function(s)
function normalize(vec)
    """
    Normalize a Vector to values between 0 and 1
    """

    return[(x - minimum(vec))/(maximum(vec) - minimum(vec)) for x in vec]
end

# Download shapefiles
url = "https://www.cbs.nl/-/media/cbs/dossiers/nederland-regionaal/wijk-en-buurtstatistieken/wijkbuurtkaart_2020_v1.zip"
name_zipfile = split(url, "/")[end]
path_zipfile = joinpath(pwd(), "downloads", name_zipfile)
if ~isfile(path_zipfile)
    download(url, path_zipfile)
end

# Extract shapefiles
path_shapefile = joinpath(pwd(), "shapefiles", "gemeente_2020_v1.shp")
if ~isfile(path_shapefile)
    r = ZipFile.Reader(path_zipfile)
    for file in r.files
        open(joinpath(pwd(), "shapefiles", file.name), "w") do io
            write(io, read(file))
        end
    end
end

# Read shapefile
table = Shapefile.Table(path_shapefile)

# Create dataframe
df = table |> DataFrame
df.Shape = Shapefile.shapes(table)

# Filter for land (i.e. not water)
row_filter = df.H2O .== "NEE"

# Apply filter
municipality = df[row_filter, :]

# Download COVID-19 data
url = "https://data.rivm.nl/covid-19/COVID-19_aantallen_gemeente_per_dag.csv"
file_path = joinpath(pwd(), "data", split(url, "/")[end])
download(url, joinpath(pwd(), "data", file_path))

# Read COVID-19 data
covid = CSV.File(file_path) |> DataFrame

# Select most recent data
actuals = covid[
    .&(.~ismissing.(covid.Municipality_name),
        covid.Date_of_publication .== maximum(covid.Date_of_publication)
        ),
    [:Municipality_name, :Total_reported]
]

# Sum multiple rows for municipalities on one day
actuals = combine(
    groupby(actuals, :Municipality_name),
    names(actuals)[2:end] .=> sum .=> names(actuals)[2:end]
)

# Join municipality shapes and COVID-19 data
covid = leftjoin(municipality, actuals, on="GM_NAAM"=>"Municipality_name")

# Add new variable (covid cases per 100,000 inhabitants)
covid.Total_reported_per_100000 = covid.Total_reported .* (100_000 ./ covid.AANT_INW)

# Values to plot
values = covid[:, :Total_reported_per_100000]
normalized_values = normalize(values)

# Colors to plot
colormap = :heat
colors = Array([cgrad(colormap)[value] for value in normalized_values])

# Create figure
plot(size=(1000, 1200), axis=false, ticks=false)
for i = 1:nrow(covid)
    plot!(covid[i, :Shape], color=colors[i])
end

# Save figure
savefig(joinpath(pwd(), "output", "thematic_map.png"))
savefig(joinpath(pwd(), "output", "thematic_map.svg"))
