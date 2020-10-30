flutter build web --release
cd build/web
git init
git remote add origin git@github.com:GameHolics/excel_parser.git
git checkout -b gh-pages
git add --all
git commit -m "update"
git push origin gh-pages -f