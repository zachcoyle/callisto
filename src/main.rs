use clap::Parser;

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Args {
    #[arg(short, long)]
    watch: bool,
}

fn main() {
    let args = Args::parse();
    println!("{}", args.watch)
}
