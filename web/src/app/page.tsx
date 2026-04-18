import Hero from "@/components/sections/Hero";
import Tools from "@/components/sections/Tools";
import Trackpad from "@/components/sections/Trackpad";
import MathSection from "@/components/sections/Math";
import Library from "@/components/sections/Library";
import Details from "@/components/sections/Details";
import CTA from "@/components/sections/CTA";
import Footer from "@/components/sections/Footer";

export default function Home() {
  return (
    <main className="relative">
      <Hero />
      <Tools />
      <Trackpad />
      <MathSection />
      <Library />
      <Details />
      <CTA />
      <Footer />
    </main>
  );
}
