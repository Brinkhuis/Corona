### A Pluto.jl notebook ###
# v0.12.17

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : missing
        el
    end
end

# ╔═╡ f3c0c18c-3ea9-11eb-1dec-9d913945500c
begin
	using CSV
	using DataFrames
	using Dates
	using Plots
	using PlutoUI
	using Shapefile
	using ZipFile
end

# ╔═╡ ce5e8eb0-3ea9-11eb-0f5e-d9494524efeb
md"# COVID-19 Cases per Municipality"

# ╔═╡ 0f099d5c-3ee5-11eb-22eb-716fd845a490
@bind cmap Radio(["Heat", "Viridis", "Magma", "Sunset", "CoolWarm", "Reds"], default="Heat")

# ╔═╡ c01bc45a-3ee3-11eb-0545-c5656dbc9bd9
md"----"

# ╔═╡ a0982244-3ee4-11eb-2d26-5d2936f1b847
md"### Settings"

# ╔═╡ a9e5b7a8-3ee4-11eb-2dae-95ebaee361e5
size = (500, 600)

# ╔═╡ 3e077378-3ee4-11eb-0330-6d8b95bae896
md"### Load Packages"

# ╔═╡ 5176b978-3ee4-11eb-3a86-157646bd4d22
md"### Get Data"

# ╔═╡ e8c1fff0-3eaa-11eb-1646-510ab72b9fdb
# Create directorties
for dir in ["data", "downloads", "shapefiles", "output"]
    path = joinpath(pwd(), dir)
    if ~ispath(path)
        mkpath(path)
    end
end

# ╔═╡ 473a932e-3eaa-11eb-3403-e3bc710fc555
# Download COVID-19 data
begin
	data_url = "https://data.rivm.nl/covid-19/COVID-19_aantallen_gemeente_per_dag.csv"
    data_path = joinpath(pwd(), "data", split(data_url, "/")[end])
    download(data_url, joinpath(pwd(), "data", data_path))
end

# ╔═╡ 240879da-3eae-11eb-1b50-7708d9135ce0
# Read COVID-19 data
begin
	covid = CSV.File(data_path, pool=false) |> DataFrame
	
	# Date the figures were update
	date_of_report = maximum(Date.(covid.Date_of_report, DateFormat("Y-m-d H:M:S")))
	
	# Earliest date for which data is available
	date_of_publ_min = minimum(covid.Date_of_publication)
	
	# Latest date for which data is available
	date_of_publ_max = maximum(covid.Date_of_publication)
	
	# Select columns of interest
	select!(covid, ["Date_of_publication", "Municipality_name", "Total_reported"])
	
	# Drop NA's
	covid = covid[completecases(covid), :]
	
	# Sum multiple data points for a municipality on a specific date
	covid = combine(
		groupby(covid, [:Date_of_publication, :Municipality_name]),
		:Total_reported .=> sum .=> :Total_reported
	)
end;

# ╔═╡ 64e19a92-3eca-11eb-3b82-e14ba130e6b1
@bind datetime DateField(default=date_of_publ_max)

# ╔═╡ 471ec664-3eaa-11eb-1fe0-a38e52f1999d
# Download shapefiles
begin
	shape_url = "https://www.cbs.nl/-/media/cbs/dossiers/nederland-regionaal/wijk-en-buurtstatistieken/wijkbuurtkaart_2020_v1.zip"
	name_zipfile = split(shape_url, "/")[end]
	path_zipfile = joinpath(pwd(), "downloads", name_zipfile)
	if ~isfile(path_zipfile)
		download(shape_url, path_zipfile)
	end
end

# ╔═╡ f385200a-3ea9-11eb-3e16-036ffd62ea07
# Extract shapefiles
begin
	name_shapefile = "gemeente_2020_v1.shp"
	path_shapefile = joinpath(pwd(), "shapefiles", name_shapefile)
	if ~isfile(path_shapefile)
		r = ZipFile.Reader(path_zipfile)
		for file in r.files
			if split(file.name, ".")[1] == split(name_shapefile, ".")[1]
				open(joinpath(pwd(), "shapefiles", file.name), "w") do io
					write(io, read(file))
				end
			end
		end
	end
end

# ╔═╡ 47377d50-3eb5-11eb-130a-63f690bf28c5
# Shapefile to dataframe
begin
	# Read shapefile
	table = Shapefile.Table(path_shapefile)
	
	# Create dataframe
	shp = table |> DataFrame
	shp.Shape = Shapefile.shapes(table)
	
	# Filter for land (i.e. not water)
	row_filter = shp.H2O .== "NEE"
	
	# Apply filter & select columns
	shp = shp[row_filter, ["GM_NAAM", "AANT_INW", "Shape"]]
end;

# ╔═╡ 2fb4f32c-3ee4-11eb-0eb0-b989926e82f7
md"### Functions"

# ╔═╡ 2c3723ba-3ed4-11eb-00f8-2b6e8ef1927a
function normalize(vec)
    """
    Normalize a Vector to values between 0 and 1
    """

    return[(x - minimum(vec))/(maximum(vec) - minimum(vec)) for x in vec]
end

# ╔═╡ 161d52e6-3ed1-11eb-1bd0-8bcd7d946dba
function color(vec, colormap)
	colors = Array([cgrad(colormap)[value] for value in normalize(vec)])
	return colors
end

# ╔═╡ 25da64be-3ecf-11eb-18b6-59759b67ef34
function chorophlet(datetime, colormap)
	# Filter on selected date
	covid_date = covid[covid.Date_of_publication .== Dates.Date(datetime), :]
	
	# Join with municipality shapes and data
	df = leftjoin(shp, covid_date, on="GM_NAAM"=>"Municipality_name")
	
	# Add column (total reported per 100,000 inhabitants)
	df.Per_100_000 = df.Total_reported .* (100_000 ./ df.AANT_INW)
	
	p = plot(size=size, axis=false, ticks=false)
	for i = 1:nrow(df)
		plot!(df[i, :Shape], color=color(df.Per_100_000, colormap)[i])
	end
	
	savefig(joinpath(pwd(), "output", "thematic_map.png"))
	
	return p
end

# ╔═╡ 3abff2be-3ee2-11eb-27ee-b92cdde85622
function chorophlet_no_data()
	title = "Select a date between $date_of_publ_min and $date_of_publ_max"
	return plot(shp.Shape, color="white", size=size,
		axis=false, ticks=false, title=title
	)
end

# ╔═╡ 1f55b380-3ee8-11eb-05a7-979744a438cf
colors = Dict(
	"Heat" => :heat,
	"Viridis" => :viridis,
	"Inferno" => :inferno,
	"Magma" => :magma,
	"Sunset" => :sunset,
	"CoolWarm" => :coolwarm,
	"Pearl" => :pearl,
	"Neon" => :neon,
	"Coffee" => :coffee,
	"Spectral" => :Spectral,
	"RedBlue" => :RdBu,
	"Reds" => :Reds,
	"Blues" => :Blues,
	"Greens" => :Greens,
	"Purples" => :Purples,
	"Oranges" => :Oranges,
	"Leonardo" => :leonardo,
	"Vermeer" => :vermeer,
	"Picasso" => :picasso,
)

# ╔═╡ ed9aa2ee-3ee2-11eb-10c7-3ff216a356e5
if Date(datetime) >= date_of_publ_min && Date(datetime) <= date_of_publ_max
	chorophlet(datetime, colors[cmap])
else
	chorophlet_no_data()
end

# ╔═╡ 31e869c2-3ed4-11eb-2bdc-17937815c701
color(1:15, colors[cmap])

# ╔═╡ 096112fc-3f0a-11eb-2bd4-ab7d2281b348
md"---"

# ╔═╡ 7836bfc8-3f0b-11eb-16cb-6794dbf0313f
md"### Preview Colors"

# ╔═╡ 286a117e-3f07-11eb-0adc-ff6b3cfd2b08
@bind test_color Select([Pair(k, k) for k in keys(colors)], default="Heat")

# ╔═╡ ae04880c-3f0a-11eb-14e1-d3e8bce1f77e
@bind samples Slider(2:20, default=10)

# ╔═╡ 42dfb7ea-3f08-11eb-0f3d-6514c39fca98
color(1:samples, colors[test_color])

# ╔═╡ Cell order:
# ╟─ce5e8eb0-3ea9-11eb-0f5e-d9494524efeb
# ╟─64e19a92-3eca-11eb-3b82-e14ba130e6b1
# ╟─0f099d5c-3ee5-11eb-22eb-716fd845a490
# ╟─ed9aa2ee-3ee2-11eb-10c7-3ff216a356e5
# ╟─31e869c2-3ed4-11eb-2bdc-17937815c701
# ╟─c01bc45a-3ee3-11eb-0545-c5656dbc9bd9
# ╟─a0982244-3ee4-11eb-2d26-5d2936f1b847
# ╠═a9e5b7a8-3ee4-11eb-2dae-95ebaee361e5
# ╟─3e077378-3ee4-11eb-0330-6d8b95bae896
# ╠═f3c0c18c-3ea9-11eb-1dec-9d913945500c
# ╟─5176b978-3ee4-11eb-3a86-157646bd4d22
# ╠═e8c1fff0-3eaa-11eb-1646-510ab72b9fdb
# ╠═473a932e-3eaa-11eb-3403-e3bc710fc555
# ╠═240879da-3eae-11eb-1b50-7708d9135ce0
# ╠═471ec664-3eaa-11eb-1fe0-a38e52f1999d
# ╠═f385200a-3ea9-11eb-3e16-036ffd62ea07
# ╠═47377d50-3eb5-11eb-130a-63f690bf28c5
# ╟─2fb4f32c-3ee4-11eb-0eb0-b989926e82f7
# ╠═2c3723ba-3ed4-11eb-00f8-2b6e8ef1927a
# ╠═161d52e6-3ed1-11eb-1bd0-8bcd7d946dba
# ╠═25da64be-3ecf-11eb-18b6-59759b67ef34
# ╠═3abff2be-3ee2-11eb-27ee-b92cdde85622
# ╠═1f55b380-3ee8-11eb-05a7-979744a438cf
# ╟─096112fc-3f0a-11eb-2bd4-ab7d2281b348
# ╟─7836bfc8-3f0b-11eb-16cb-6794dbf0313f
# ╟─286a117e-3f07-11eb-0adc-ff6b3cfd2b08
# ╟─ae04880c-3f0a-11eb-14e1-d3e8bce1f77e
# ╟─42dfb7ea-3f08-11eb-0f3d-6514c39fca98
